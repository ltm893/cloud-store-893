## Summary

<!-- What changed and why -->

## Test plan

- [ ] `npm run test:unit`
- [ ] Manual checks (if applicable):

## Versioning

- [ ] [CHANGELOG.md](../CHANGELOG.md) updated under **`[Unreleased]`** (if deploy- or user-notable)
- [ ] **`package.json` version** bumped (release PR only — see [docs/versioning.md](../docs/versioning.md))
- [ ] After merge to **`dev`**: deploy with  
      `./scripts/oci/redeploy-app-code.sh "<label matching this PR or CHANGELOG>"`
