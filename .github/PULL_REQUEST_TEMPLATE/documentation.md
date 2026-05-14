### Summary

Describe the memo.wz documentation change.

### Documentation Changed

List the README, examples, contributing guide, issue templates, pull request
templates, or annotation docs changed by this pull request.

### Reader Impact

Explain who benefits from this documentation change:

- Users caching values in WezTerm.
- Users persisting plugin or configuration state.
- Contributors changing memo.wz internals.

### Examples Touched

```lua
-- cache, key, or state example changed by this pull request
```

### Behavior Change

- [ ] Documentation only
- [ ] Documents an existing behavior
- [ ] Documents a new behavior

If this documents a new behavior, link to the implementation pull request or
commit.

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

