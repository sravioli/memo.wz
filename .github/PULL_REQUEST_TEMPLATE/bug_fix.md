### Summary

Describe the bug fixed in memo.wz and the user-visible cache or state behavior
that changed.

### Reproduction

Provide the smallest setup that reproduced the issue.

```lua
-- cache, key, or state usage that reproduced the bug
```

### Root Cause

Explain why memoization, key generation, serialization, file persistence, reload
behavior, or error handling was wrong.

### Fix

Describe the implementation change and why it fixes the problem.

### Regression Test

Describe the regression test added or updated.

### Compatibility Impact

- [ ] Non-breaking
- [ ] Potentially breaking
- [ ] Breaking

If this changes behavior intentionally, explain why the new behavior is correct.

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

