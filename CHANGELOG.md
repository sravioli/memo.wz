# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## [0.2.0](https://github.com/sravioli/memo.wz/compare/0ac7388d8b32efc2172f7ba369416872391cfbc0..0.2.0) - 2026-11-15
#### Features
- (**cache**) add entry ttl and read-through fetch - ([7ba529a](https://github.com/sravioli/memo.wz/commit/7ba529a076cbc832f2d083fb349a09538d9f3918)) - sravioli
- (**state**) add atomic writes and replace set - ([94c16fe](https://github.com/sravioli/memo.wz/commit/94c16fe2b17189dbe376fe03209a81aea33edd17)) - sravioli
#### Bug Fixes
- (**cache**) handle real wezterm.GLOBAL proxies - ([5a3a051](https://github.com/sravioli/memo.wz/commit/5a3a0511a9d5a79a6c3510dec897cafe4863b3e4)) - sravioli
- (**state**) store lists and merge in plain Lua - ([6dce7d5](https://github.com/sravioli/memo.wz/commit/6dce7d5f9bddc735c544ddeaaa473939543cd55a)) - sravioli
- (**state**) use unique temp files, copy backups - ([8fbaeec](https://github.com/sravioli/memo.wz/commit/8fbaeec3c115c93e0649da52acd1ca1857277cfa)) - sravioli
- (**state**) check writes and log rollback - ([6fef462](https://github.com/sravioli/memo.wz/commit/6fef462c956c9ffa8baf31252bc3d8c2b8ecb967)) - sravioli
#### Performance Improvements
- (**bootstrap**) keep plugin list across reloads - ([a70394a](https://github.com/sravioli/memo.wz/commit/a70394a4454c7cfebd768950b2a0958a2c87bac3)) - sravioli
- (**bootstrap**) share plugin discovery snapshot - ([0ac7388](https://github.com/sravioli/memo.wz/commit/0ac7388d8b32efc2172f7ba369416872391cfbc0)) - sravioli
#### Documentation
- (**readme**) describe atomic write guarantees - ([2f8c51c](https://github.com/sravioli/memo.wz/commit/2f8c51c952e7ff5f346e9819d53e114601cdedb7)) - sravioli
- (**readme**) update plugin READMEs - ([acc62c8](https://github.com/sravioli/memo.wz/commit/acc62c8a22b804faa754f609c87c0a9686ea036e)) - sravioli
- (**readme**) clarify namespace wrapper scope - ([705a8a9](https://github.com/sravioli/memo.wz/commit/705a8a9a508a27bff114cfee6a3cdd9454286468)) - sravioli
#### Tests
- (**state**) cover concurrent-safe atomic writes - ([c96103f](https://github.com/sravioli/memo.wz/commit/c96103f81b8d0aece8c3aacc2c5d777e9509d463)) - sravioli
- run memo against a real wezterm.GLOBAL - ([cd6fb97](https://github.com/sravioli/memo.wz/commit/cd6fb977acfe174c69abfc6cd240f1fc1f15bfac)) - sravioli

- - -

## [0.1.3](https://github.com/sravioli/memo.wz/compare/183280cc338d1bc0217b825243cab0baed970e94..0.1.3) - 2026-05-14
#### Documentation
- (**github**) add pull request templates - ([0438c7a](https://github.com/sravioli/memo.wz/commit/0438c7a6a4c8e815c43ddcc1a02908a5aa83fd2a)) - sravioli
- (**github**) polish issue templates - ([3083161](https://github.com/sravioli/memo.wz/commit/3083161a0c7341b9475fdff1c669db0b91c770c1)) - sravioli
- (**lua**) polish comment wording - ([cc43299](https://github.com/sravioli/memo.wz/commit/cc43299933d6a5c749011363c3dd0af5d2f04990)) - sravioli
- (**lua**) polish comment wording - ([fcbdf6f](https://github.com/sravioli/memo.wz/commit/fcbdf6fa2bce345eeec7223ada8979b2e8e6f345)) - sravioli
- (**readme**) improve readme consistency - ([da6d0d5](https://github.com/sravioli/memo.wz/commit/da6d0d5c759b6024964e5d386ee5bf6464fe88ea)) - sravioli
- (**readme**) improve readme clarity - ([183280c](https://github.com/sravioli/memo.wz/commit/183280cc338d1bc0217b825243cab0baed970e94)) - sravioli

- - -

## [0.1.2](https://github.com/sravioli/memo.wz/compare/e4d981d8b807e1a24050cd6e35ca41cc2f22a347..0.1.2) - 2026-04-10
#### Documentation
- add type annotations section to README - ([e4d981d](https://github.com/sravioli/memo.wz/commit/e4d981d8b807e1a24050cd6e35ca41cc2f22a347)) - sravioli

- - -

## [0.1.1](https://github.com/sravioli/memo.wz/compare/6ff714deb343a09c3a57662539772a30d85aca76..0.1.1) - 2026-04-02
#### Bug Fixes
- (**cache**) avoid repeated set calls - ([18bbfaf](https://github.com/sravioli/memo.wz/commit/18bbfafd9e7bfbb635654c1349edd9cdacf5f63d)) - sravioli
- (**cocogitto**) set correct repository name - ([6ff714d](https://github.com/sravioli/memo.wz/commit/6ff714deb343a09c3a57662539772a30d85aca76)) - sravioli
- streamline config files - ([3fc182c](https://github.com/sravioli/memo.wz/commit/3fc182ccf6e3288fe1601155d4c18ff66a51be3c)) - sravioli
#### Tests
- (**cache**) add set safeguard tests - ([72bad71](https://github.com/sravioli/memo.wz/commit/72bad7179e4cf9e2439e5be5068f285b2c28b8c0)) - sravioli
#### Style
- format with stylua - ([53c8c6f](https://github.com/sravioli/memo.wz/commit/53c8c6f0514561e0be6ea41c13dbe8b9e4770e88)) - sravioli

- - -

## [0.1.0](https://github.com/sravioli/wezterm/compare/e312b69d8464de3ac9bd2b775ef5be7243f72cfe..0.1.0) - 2026-03-19
#### Features
- ![BREAKING](https://img.shields.io/badge/BREAKING-red) (**hash**) rm hash to use faster key serialization - ([8f622b9](https://github.com/sravioli/wezterm/commit/8f622b9e10642aceaef25bbfa3c25dfd4191ef1c)) - sravioli
- implement cache, hash and state - ([edd342a](https://github.com/sravioli/wezterm/commit/edd342a0fb5ae7ab3d52dc08a4edf196b77f6239)) - sravioli
#### Bug Fixes
- (**lint**) resolve linter issues - ([ffca05c](https://github.com/sravioli/wezterm/commit/ffca05cb9f9c0297faf1ad5ea7b5425c1cd5159b)) - sravioli
- (**lint**) resolve luacheck lint warnings - ([97ee049](https://github.com/sravioli/wezterm/commit/97ee04940dfea3bb1299f71d95b551fba035025c)) - sravioli
#### Documentation
- (**init**) add documentation - ([7861801](https://github.com/sravioli/wezterm/commit/78618013c52ac7efe51d5ac5750681c7d7e488de)) - sravioli
- update readme - ([540acb1](https://github.com/sravioli/wezterm/commit/540acb19498221ccdacf5b92a960575aad03dec1)) - sravioli
#### Tests
- fix failing tests - ([54281a8](https://github.com/sravioli/wezterm/commit/54281a8c3e4bcab4beceba09cc799a9360ba7032)) - sravioli
- state reload tests - ([ed947ec](https://github.com/sravioli/wezterm/commit/ed947ec728af8aba9511062c37d6c323edc24da8)) - sravioli
- increase coverage - ([1764874](https://github.com/sravioli/wezterm/commit/1764874bc396b3e1a0674efb4ce7b7fc296ead18)) - sravioli
- add tests - ([ddc638a](https://github.com/sravioli/wezterm/commit/ddc638a0f29cc0e92fb05aebb8d78113135247d7)) - sravioli
#### Continuous Integration
- add lint, test and release jobs - ([0092985](https://github.com/sravioli/wezterm/commit/00929858417d314606ff805fdd10c47c0c229300)) - sravioli
#### Style
- formatting - ([0827549](https://github.com/sravioli/wezterm/commit/082754992bea7749445c8895c63d8ec9ec490e3c)) - sravioli

- - -

Changelog generated by [cocogitto](https://github.com/cocogitto/cocogitto).