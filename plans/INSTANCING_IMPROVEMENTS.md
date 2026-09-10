I would implement the cache as a scene-owned service. Every logical object receives an instance or clone; the cached source mesh never represents an actual scene object.

### Scope and design decisions

| Concern | Decision |
|---|---|
| Cache owner | `SceneBinding`, because Babylon meshes belong to one Babylon scene |
| Cache key | `geometryId` plus geometry-affecting node inputs such as `faceUvs` |
| Concurrent loading | Cache the pending `Promise`, not only the completed mesh |
| Source lifetime | Reference counted and swept after each `setScene()` |
| Normal object | `InstancedMesh` sharing source geometry and material |
| Custom node material | Regular clone sharing geometry, with its own material |
| Physics | Separate body and shape for every logical object |
| Imported collider | Stored beside the cached source and reused as shape-construction input |
| Geometry change | Retire the current entry; keep it alive until its existing users are gone |
| Robot links | Follow-up work; their loading and articulated physics use a separate path |

### 1. Add a `SourceMeshCache` class

Create:

[SourceMeshCache.ts](/workspace/src/simulator/babylonBindings/createSceneObjects/SourceMeshCache.ts)

Its public API should stay small:

```ts
export interface SourceMeshHandle {
  readonly key: string;
  readonly visual: AbstractMesh;
  readonly collisionSource?: Mesh;
  readonly isInstance: boolean;
  release(): void;
}

export class SourceMeshCache {
  constructor(
    scene: BabylonScene,
    buildSource?: SourceMeshBuilder,
  );

  acquire(
    geometryId: string,
    geometry: Geometry,
    options: {
      name: string;
      faceUvs?: RawVector2[];
      material?: Material;
    },
  ): Promise<SourceMeshHandle>;

  retireGeometry(geometryId: string): void;
  sweep(): void;
  dispose(): void;
}
```

Internally, each entry should resemble:

```ts
interface SourceMeshEntry {
  key: string;
  geometryId: string;
  source: Mesh;
  collider?: Mesh;
  references: number;
  retired: boolean;
}

interface PendingSourceMeshEntry {
  promise: Promise<SourceMeshEntry>;
  references: number;
  retired: boolean;
}
```

The map contains pending and completed entries:

```ts
private entries_ = new Map<string, CacheEntry>();
```

Storing the pending promise prevents two simultaneous calls from both invoking `ImportMeshAsync`.

If source construction fails, remove that entry before rethrowing. Otherwise one failed request would poison that geometry for the rest of the session.

### 2. Separate source construction from object construction

Refactor [`buildGeometry()`](/workspace/src/simulator/babylonBindings/createSceneObjects/createObjects.ts:58) so it creates cache-owned resources only:

```ts
interface BuiltGeometrySource {
  visual: Mesh;
  collider?: Mesh;
}
```

The builder should:

- Create or import the geometry.
- Separate imported visual and collider meshes.
- Merge visual meshes where the current implementation does so.
- Preserve imported materials.
- Dispose temporary import roots after merging.
- Leave the source enabled with `visibility = 1`.
- Set `source.isVisible = false`.
- Set `source.isPickable = false`.
- Add no physics body.
- Add no scene-node ID metadata.
- Give it a reserved name such as `__geometry_source__:cubeRed2In`.

The source must remain enabled because Babylon needs it when rendering instances. `isVisible = false` hides the source itself while allowing instances to remain visible.

Remove the current name-based lookup completely:

```ts
bScene_.meshes.filter(m => m.name.startsWith(node.geometryId))
```

### 3. Define cache variants

The main cache namespace should be `geometryId`. Within it, distinguish inputs that change vertex data.

For the current builders, `faceUvs` changes generated geometry, so the variant key can be:

```ts
`${geometryId}:${faceUvFingerprint(faceUvs)}`
```

Use a deterministic fingerprint helper rather than object identity. The arrays contain plain numeric values, so a normalized numeric serialization is sufficient.

The `Geometry` object itself does not have to be serialized into every key. [`setScene()`](/workspace/src/simulator/babylonBindings/SceneBinding.ts:1296) already receives geometry patches. When the definition for an ID changes, retire all active variants for that geometry ID before creating replacements.

Node material overrides should initially use clones:

```ts
if (options.material) {
  visual = source.clone(options.name);
  visual.material = createMaterial(options.name, options.material, scene);
} else {
  visual = source.createInstance(options.name);
}
```

This preserves per-node material behavior. Babylon instances cannot have independent materials. A later optimization could introduce material-specific source variants for cases where many objects have identical overrides.

Regardless of which path is used, explicitly restore logical-object state:

```ts
visual.isVisible = true;
visual.isPickable = true;
```

Do not depend on properties copied from the hidden source.

### 4. Make the first object an instance too

The source mesh should never be returned as a logical object. Even the first object gets:

```ts
source.createInstance(nodeName)
```

That fixes the current ownership problem:

```text
Hidden cache source
  ├── Low Red Cube
  ├── High Red Cube
  └── Middle Red Cube
```

Deleting any cube disposes only that cube. The other instances and source remain intact.

### 5. Track handles in `SceneBinding`

Add a parallel mapping near `nodes_`:

```ts
private objectSourceHandles_: Dict<SourceMeshHandle> = {};
private sourceMeshCache_: SourceMeshCache;
```

Construct the cache in the [`SceneBinding` constructor](/workspace/src/simulator/babylonBindings/SceneBinding.ts:100):

```ts
this.sourceMeshCache_ = new SourceMeshCache(this.bScene_);
```

Change `createObject()` to accept the cache and return enough information to record the handle:

```ts
interface CreatedObject {
  node: AbstractMesh;
  sourceHandle: SourceMeshHandle;
}
```

Then [`createNode_()`](/workspace/src/simulator/babylonBindings/SceneBinding.ts:539) should:

1. Acquire the handle.
2. Assign the node’s Babylon ID and metadata.
3. Record the handle by scene node ID.
4. Apply parent, transform, visibility, and physics.
5. Release the handle if any later creation step throws.

The hidden source should have cache metadata only:

```ts
{
  sourceMeshCache: true,
  geometryId,
}
```

It must not have `SceneMeshMetadata.id`, so collision and node lookup code cannot mistake it for a logical object.

### 6. Release entries during node destruction

Update [`destroyNode_()`](/workspace/src/simulator/babylonBindings/SceneBinding.ts:956):

```ts
const handle = this.objectSourceHandles_[id];

if (handle) {
  handle.release();
  delete this.objectSourceHandles_[id];
}
```

Dispose the logical mesh before or during release. Disposing an `InstancedMesh` unregisters it from the source without affecting sibling instances.

For a custom-material clone, dispose its owned material and textures explicitly. Do not dispose imported/shared source materials when deleting an instance. The handle should carry ownership information or expose a `disposeVisual()` method so that this distinction stays inside the cache.

### 7. Retire changed geometry safely

At the start of `setScene()`, inspect `patch.geometry`. For every add, remove, inner change, or outer change:

```ts
this.sourceMeshCache_.retireGeometry(geometryId);
```

Retirement should:

- Remove the entry from active lookup immediately.
- Keep its source alive while `references > 0`.
- Put subsequent acquisitions into a new entry.
- Dispose it during `sweep()` once its reference count reaches zero.

This matters because objects using the old and new definitions can temporarily coexist while `setScene()` processes its sequential updates.

Call:

```ts
this.sourceMeshCache_.sweep();
```

after node removal and creation finish. Put cleanup in a `finally` block so retired zero-reference entries are also cleaned after an update error.

The same delayed sweep helps scene changes. Since removals happen first, a shared geometry may briefly reach zero references before objects from the next scene acquire it. Sweeping at the end allows the next scene to reuse it without another import.

### 8. Refactor collider handling

Currently [`createObject()`](/workspace/src/simulator/babylonBindings/createSceneObjects/createObjects.ts:197) writes the imported collider ID into `node.physics`:

```ts
node.physics.colliderId = ret.collider.id;
```

Remove this mutation. It modifies scene or template state and ties physics to one particular import.

Instead, store the collider in the cache entry and associate it with every acquired handle:

```ts
handle.collisionSource
```

Extend [`restorePhysicsToObject()`](/workspace/src/simulator/babylonBindings/SceneBinding.ts:1121) to receive the collision source directly:

```ts
restorePhysicsToObject(
  visual,
  objectNode,
  nodeId,
  scene,
  collisionSource,
);
```

Each logical object still receives its own:

- `PhysicsBody`
- `PhysicsShape`
- mass and motion type
- friction and restitution
- collision-filter registration

For mesh collision shapes, use the cached collider as the mesh passed into shape construction. Validate that Havok copies the collider geometry when constructing each shape. If it retains mutable transform state, create a hidden collider clone per object instead; this still avoids another GLB import and parse.

Keep `colliderId` support for existing user-authored scenes that deliberately reference another scene mesh. The cache-provided collider should take precedence only for a collider extracted from the object’s GLB.

### 9. Recreate objects when their render variant changes

[`updateObject_()`](/workspace/src/simulator/babylonBindings/SceneBinding.ts:660) currently tries to modify materials in place. That is unsafe for `InstancedMesh`, whose material comes from its source.

Recreate the logical visual when any of these change:

- `geometryId`
- `material`
- `faceUvs`

The recreation sequence should be:

1. Remove the old physics body.
2. Dispose the old logical instance or clone.
3. Release its source handle.
4. Acquire the correct source variant.
5. Restore ID, metadata, parent, transform, visibility, selection, and physics.

Position, orientation, scale, visibility, name, parent, and physics-only changes can continue updating the existing logical object.

### 10. Add explicit cache disposal

`SceneBinding` currently has no general disposal method. Add one that cleans up:

```ts
dispose(): void {
  // Dispose logical nodes and robot bindings first.
  this.sourceMeshCache_.dispose();
  // Dispose remaining SceneBinding-owned helpers.
}
```

The cache’s `dispose()` should:

- Reject or ignore completion from stale pending loads.
- Dispose every source and cached collider.
- Dispose imported materials and textures owned by each entry.
- Clear active and retired maps.

Wire this into the eventual `Space`/Babylon-scene teardown path. Even if `Space` currently lives for the application lifetime, defining ownership now prevents leaks in tests and future scene recreation.

### 11. Tests

Add focused tests in:

[test/simulator/SourceMeshCache.spec.ts](/workspace/test/simulator/SourceMeshCache.spec.ts)

Use Babylon’s `NullEngine` and inject a fake asynchronous source builder. This avoids real network requests while testing cache behavior.

Required cases:

1. Two sequential acquisitions build once and share the same source.
2. Two concurrent acquisitions build once.
3. A failed build is removed and can be retried.
4. The first logical object is an instance, not the source.
5. Deleting one instance leaves its siblings valid.
6. An entry remains alive while it has references.
7. An unused entry is disposed during `sweep()`.
8. A geometry change retires the old entry and builds a new one.
9. An unchanged geometry survives a scene transition where references briefly reach zero.
10. Different `faceUvs` produce separate sources.
11. A material override produces an independent clone and cannot mutate the source material.
12. Removing a custom-material clone disposes only its owned material.
13. Each instance receives a separate physics body and shape.
14. Two objects using one cached imported collider collide at their own transforms.
15. Hidden sources are invisible, unpickable, and absent from scene-node lookup.

Add one integration test around `SceneBinding.setScene()` with a mocked builder:

- Create a scene containing several `cubeRed2In` objects.
- Assert one build.
- Assert all logical node IDs resolve correctly.
- Remove whichever object was created first.
- Assert remaining objects still render and resolve.
- Change the geometry definition.
- Assert exactly one additional build.

### 12. Manual verification

Use a scene with repeated poms, cubes, baskets, and cones.

With browser caching disabled in DevTools:

- Each unique GLB should appear once during scene creation.
- Repeated objects should add no GLB requests.
- Switching to another scene that shares a still-active geometry should reuse the source during that `setScene()` transition.
- Changing a geometry URI should cause exactly one new request.
- Deleting the first-created object should leave all others intact.
- Picking, gizmos, scripts, visibility toggles, collisions, and physics motion should remain independent.

Also inspect the Babylon scene:

```text
one hidden source per geometry/UV variant
N logical instances for N ordinary objects
custom-material clones only where required
no physics bodies on hidden sources
```

Finally run the targeted Jest tests, the full test suite, lint on the changed files, and the production webpack build.

The initial change should cover objects created through [`createSceneObjects/createObjects.ts`](/workspace/src/simulator/babylonBindings/createSceneObjects/createObjects.ts). Robot GLBs are loaded through [`createRobotObjects/createLink.ts`](/workspace/src/simulator/babylonBindings/createRobotObjects/createLink.ts:31); they can later reuse the source-building and pending-promise infrastructure, but articulated link physics needs separate validation before converting those meshes to instances.
