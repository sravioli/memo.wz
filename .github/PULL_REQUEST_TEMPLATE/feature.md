### Summary

Describe the new memo.wz feature and the user-facing cache or state workflow it
enables.

### Motivation

Explain why this belongs in memo.wz. Focus on memoization, stable key generation,
WezTerm global cache behavior, file-backed state, or state reload behavior.

### API Sketch

```lua
-- show intended cache, key, state, or setup usage
```

### Behavior

Describe how the feature behaves, including default options, cache lifetime,
state path behavior, serialization, reload behavior, and failure cases.

### Compatibility

- [ ] Non-breaking
- [ ] Potentially breaking
- [ ] Breaking

If this is potentially breaking or breaking, explain the migration path.

### Tests

Describe the tests added or updated for this behavior.

### Documentation

Describe the README, examples, annotation, or template changes made for this
feature.

### Checklist

- [ ] The change is scoped to memo.wz.
- [ ] Public API changes are documented, if applicable.
- [ ] Cache, key, or state behavior is covered by tests, if applicable.
- [ ] Existing persisted state remains compatible.
- [ ] Required checks pass:
  - [ ] `busted --verbose`
  - [ ] `luacheck .`
  - [ ] `stylua --check .`
  - [ ] `selene --display-style=quiet .`

