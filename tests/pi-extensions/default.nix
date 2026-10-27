# Runs the regression tests for the owned pi extensions in
# modules/home/pi/extensions/ against the real @earendil-works/pi-tui that
# matches the installed pi. The pi-coding-agent values they import come from
# ./stubs, because the real package is compiled into the pi binary.
#
#   nix build .#checks.x86_64-linux.pi-extensions
#
# After a pi upgrade, bump pi-tui in package.json to the same version and
# refresh the lock with `npm install --package-lock-only --ignore-scripts`.
{
  importNpmLock,
  lib,
  nodejs_24,
  runCommand,
}:

let
  nodeModules = importNpmLock.buildNodeModules {
    npmRoot = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./package.json
        ./package-lock.json
      ];
    };
    nodejs = nodejs_24;
  };
in
runCommand "pi-extension-tests"
  {
    nativeBuildInputs = [ nodejs_24 ];
  }
  ''
    mkdir -p work/extensions work/tests work/node_modules/@earendil-works
    cp ${../../modules/home/pi/extensions/compact-until.ts} work/extensions/compact-until.ts
    cp ${./compact-until.test.ts} work/tests/compact-until.test.ts
    cp ${../../modules/home/pi/extensions/expandable-bash-command.ts} work/extensions/expandable-bash-command.ts
    cp ${./expandable-bash-command.test.ts} work/tests/expandable-bash-command.test.ts
    cp -r ${nodeModules}/node_modules/. work/node_modules/
    chmod -R u+w work/node_modules
    cp -r ${./stubs/pi-coding-agent} work/node_modules/@earendil-works/pi-coding-agent

    cd work
    node --test --test-reporter=spec tests/*.test.ts | tee "$out"
  ''
