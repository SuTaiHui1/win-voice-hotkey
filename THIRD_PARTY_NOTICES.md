# Third-party notices

## AutoHotkey 2.0.30

- Upstream: https://github.com/AutoHotkey/AutoHotkey
- Exact release: https://github.com/AutoHotkey/AutoHotkey/releases/tag/v2.0.30
- Runtime: unmodified `AutoHotkey64.exe`, extracted from the official portable ZIP.
- License: GNU General Public License version 2; full text in `third-party/AutoHotkey-LICENSE.txt` and the release's `app/dependencies/license.txt`.
- Corresponding source: official `v2.0.30` source archive, distributed inside each binary package as `third-party-sources/AutoHotkey-v2.0.30-source.zip`. The archive retains upstream build files, embedded libraries, and original copyright and license notices. Follow its README for runtime build instructions; the project build uses the pinned publisher binary.
- All downloaded files are pinned with SHA-256 in `dependencies.lock.json`. The runtime ZIP digest was checked against the publisher's release page. The source digest records the official source downloaded for this version.

The interpreter is distributed separately from readable application scripts. No AutoHotkey source is relabeled as original project work. No Microsoft Windows or .NET system binary is redistributed.

The release does not use Ahk2Exe or embed the interpreter into a compiled script executable. The launcher starts the independent unmodified interpreter as a child process with a readable `.ahk` entry point. The installer's embedded ZIP is a distribution container. GPL v2 section 2 describes separate works and mere aggregation; section 3(a) permits binary distribution accompanied by corresponding source. This packaging plan applies those provisions to the separate runtime and includes its source rather than substituting a project MIT notice for the runtime license. See the [official AutoHotkey license text](https://www.autohotkey.com/docs/v2/license.htm).

## Removed development-only dependency

The earlier development workspace contains Descolada/UIA-v2 under MIT. The current application include graph does not use it. Its code and the retired focus/IA2 adapters are not included in this repository or its binary packages. Do not copy that library back without retaining its original license and notices.

## Project-specific source

The application's AHK/C# code originated as a local Win+H prototype. No project license or application-specific copyright header was present in the supplied files. The owner must approve a license before public publication. See `LICENSE-PENDING.txt` until a real `LICENSE` replaces it.
