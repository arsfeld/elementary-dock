# Sharp icons, from the extras branch of arsfeld/elementary-dock.
# IconMath.vala must not touch GTK: the unit test links only it and runs
# inside the Nix build sandbox.
icons_core_sources = files(
    'IconMath.vala',
)

icons_sources = icons_core_sources + files(
    'IconResolution.vala',
)

icons_test = executable(
    'icon-math-test',
    icons_core_sources + files('tests' / 'IconMathTest.vala'),
    dependencies: dependencies,
)

test('icon-math', icons_test)
