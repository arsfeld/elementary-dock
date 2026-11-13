# Folder stacks, from the extras branch of arsfeld/elementary-dock.
# Core files must not touch widgets that need a display: the unit test links
# only them and runs inside the Nix build sandbox. FanMath is core too: pure
# geometry, no widgets.
stacks_core_sources = files(
    'AppCenterJobs.vala',
    'AppFolders.vala',
    'FanMath.vala',
    'LauncherProgress.vala',
    'StackConfig.vala',
    'StackEntry.vala',
    'StackList.vala',
    'StackSource.vala',
)

stacks_sources = stacks_core_sources + files(
    'FanLayout.vala',
    'FanPopover.vala',
    'GridCell.vala',
    'GridPopover.vala',
    'StackItem.vala',
    'StackPile.vala',
    'StackProgressBar.vala',
    'StackRender.vala',
    'StackStore.vala',
    'StackStyle.vala',
)

stacks_test = executable(
    'stacks-test',
    stacks_core_sources + files('tests' / 'StackTests.vala'),
    dependencies: dependencies,
)

test('stacks', stacks_test)
