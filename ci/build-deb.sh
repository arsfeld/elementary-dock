#!/bin/sh
# Builds the .deb in an elementary OS container (ghcr.io/elementary/docker),
# from a checkout at $PWD, and leaves it in ./dist. Used by
# .github/workflows/ci.yml; runs the same locally:
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/elementary/docker:stable \
#     sh -c 'git config --global --add safe.directory /src && ci/build-deb.sh'
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates git devscripts equivs lintian >/dev/null

# Each build's version sorts after the last, and after a rebase onto a new
# elementary release: upstream version, commit date, commit.
upstream=$(sed -n "s/^ *version: '\([^']*\)',\$/\1/p" meson.build | head -n1)
# Commit time in UTC to the second: same-day builds must not sort by hash.
date=$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y%m%d%H%M%S)
sha=$(git rev-parse --short=8 HEAD)
version="$upstream+extras.git$date.$sha"
DEBEMAIL="alex@rosenfeld.one" DEBFULLNAME="Alexandre Rosenfeld" \
  dch --newversion "$version" --distribution noble --force-distribution \
  "Build of $(git rev-parse HEAD)."

mk-build-deps --install --remove --tool 'apt-get -y -qq --no-install-recommends' debian/control >/dev/null
# The extras' unit tests (stacks, zoom-math, icon-math) run in dh_auto_test.
dpkg-buildpackage -b -us -uc

mkdir -p dist
mv ../*.deb ../*.buildinfo ../*.changes dist/
echo "$version" > dist/VERSION

lintian --allow-root --info dist/*.deb || echo "lintian reported issues (not fatal)"
