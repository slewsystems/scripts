/*
 *
 * Description:
 * This layout is a twist on the 3Column Middle layout to
 * better accommodate ultra-wide monitors.
 *
 * Notes:
 * Due to a limitation of Amethyst, the expand/shrink main pane size keybindings
 * are bound to "Custom Command 3" and "Custom Command 4" respectively. Similarly,
 * the increase/decrease main pane count keybindings are bound to "Custom Command 1"
 * and "Custom Command 2" respectively.
 *
 * Keybindings:
 * - increaseMain: Increase main pane count (or leave carousel mode)
 * - decreaseMain: Decrease main pane count (or enter carousel mode)
 * - expandMain: Increase main pane size
 * - shrinkMain: Decrease main pane size
 *
 * Dev Notes:
 * https://github.com/ianyh/Amethyst/blob/development/docs/custom-layouts.md
 * https://github.com/ianyh/Amethyst/tree/development/AmethystTests/Model/CustomLayouts
 *
 * To add to Amethyst:
 * cp ./ultra-wide.js "$HOME/Library/Application Support/Amethyst/Layouts"
 * Then restart Amethyst and add this to your layouts
 *
 */

function layout() {
  const maxMainPaneCount = 8;
  const minMainPanelRatio = 0.2;
  const maxMainPanelRatio = 0.9;
  const paneResizeStep = 0.05; // TODO: use the 'window-resize-step' amount from Amethyst

  const LAYOUT_MODES = {
    CAROUSEL: 'carousel',
    CENTER: 'center',
    GRID: 'grid',
  }

  const partitionWindows = (windows, minWindowsPerPane = 0) => {
    const splitIndex = Math.max(
      Math.ceil(windows.length / 2),
      minWindowsPerPane
    );

    return [windows.slice(0, splitIndex), windows.slice(splitIndex)];
  };

  // TODO: add ability to pick a direction (up, down, left, right) instead of just 'vertical'
  const splitPane = (pane, splitVertical) => {
    const frameA = {
      y: pane.y,
      height: splitVertical ? pane.height / 2 : pane.height,
      x: pane.x,
      width: splitVertical ? pane.width : pane.width / 2,
    };
    const frameB = {
      y: splitVertical ? frameA.y + frameA.height : frameA.y,
      height: splitVertical ? pane.height / 2 : pane.height,
      x: splitVertical ? frameA.x : frameA.x + frameA.width,
      width: splitVertical ? pane.width : pane.width / 2,
    };

    return [frameA, frameB];
  };

  const bspWindowPanes = (windows, pane, splitVertical = true) => {
    if (windows.length === 0) return {};
    if (windows.length === 1) return { [windows[0].id]: pane };

    const [windowsA, windowsB] = partitionWindows(windows);
    const [paneA, paneB] = splitPane(pane, splitVertical);

    return {
      ...bspWindowPanes(windowsA, paneA, !splitVertical),
      ...bspWindowPanes(windowsB, paneB, !splitVertical),
    };
  };

  const partitionWindowPanes = (windows, pane) => {
    const frameWidth = pane.width / windows.length;

    return windows.reduce(
      (frames, window, index) => ({
        ...frames,
        [window.id]: {
          y: pane.y,
          x: pane.x + frameWidth * index,
          height: pane.height,
          width: frameWidth,
        },
      }),
      {}
    );
  };

  const calculateNewLayoutState = (
    { mainPaneCount: originalMainPaneCount, layoutMode: originalLayoutMode },
    mainPaneCountDelta
  ) => {
    const mainPaneCount = Math.min(
      Math.max(originalMainPaneCount + mainPaneCountDelta, -maxMainPaneCount),
      maxMainPaneCount
    );

    let layoutMode = originalLayoutMode;

    if (mainPaneCount === 0) {
      layoutMode = LAYOUT_MODES.GRID;
    } else if (mainPaneCountDelta < 0 && originalLayoutMode == LAYOUT_MODES.GRID) {
      layoutMode = LAYOUT_MODES.CENTER;
    } else if (mainPaneCountDelta > 0 && originalLayoutMode == LAYOUT_MODES.GRID) {
      layoutMode = LAYOUT_MODES.CAROUSEL;
    }

    return { mainPaneCount, layoutMode };
  };

  return {
    name: '3Column Ultra Wide',
    initialState: {
      mainPaneRatio: 0.6,
      mainPaneCount: 2,
      layoutMode: LAYOUT_MODES.CAROUSEL,
    },
    commands: {
      increaseMain: {
        description: 'Increase main pane count (or leave carousel mode)',
        updateState: (state) => ({
          ...state,
          ...calculateNewLayoutState(state, +1),
        }),
      },
      decreaseMain: {
        description: 'Decrease main pane count (or enter carousel mode)',
        updateState: (state) => ({
          ...state,
          ...calculateNewLayoutState(state, -1),
        }),
      },
      expandMain: {
        description: 'Increase main pane size',
        updateState: (state) => ({
          ...state,
          mainPaneRatio: Math.min(
            state.mainPaneRatio + paneResizeStep,
            maxMainPanelRatio
          ),
        }),
      },
      shrinkMain: {
        description: 'Decrease main pane size',
        updateState: (state) => ({
          ...state,
          mainPaneRatio: Math.max(
            state.mainPaneRatio - paneResizeStep,
            minMainPanelRatio
          ),
        }),
      },
    },
    getFrameAssignments: (windows, screenFrame, state) => {
      if (windows.length === 0) return {};
      const mainPaneCount = Math.abs(state.mainPaneCount);
      const mainPaneWindows = windows.slice(0, mainPaneCount);
      const secondaryPaneWindows = windows.slice(mainPaneCount);

      const mainPaneWidth = screenFrame.width * state.mainPaneRatio;
      const secondaryPaneWidth = screenFrame.width - mainPaneWidth;

      switch (state.layoutMode) {
        case LAYOUT_MODES.CAROUSEL: {
          // divide by two so main pain is as big as center + right when in center mode
          const leftPaneWidth =
            secondaryPaneWindows.length > 0 ? secondaryPaneWidth / 2 : 0;

          const leftPane = {
            ...screenFrame,
            width: leftPaneWidth,
          };
          const mainPane = {
            ...screenFrame,
            x: leftPane.x + leftPane.width,
            width: screenFrame.width - leftPane.width,
          };

          return {
            ...partitionWindowPanes(mainPaneWindows, mainPane),
            ...bspWindowPanes(secondaryPaneWindows, leftPane, true),
          };
        }
        case LAYOUT_MODES.GRID: {
          return {
            ...bspWindowPanes(windows, screenFrame, false),
          };
        }
        case LAYOUT_MODES.CENTER: {
          const [leftSecondaryPaneWindows, rightSecondaryPaneWindows] =
            partitionWindows(secondaryPaneWindows, 2);

          const leftPaneWidth =
            leftSecondaryPaneWindows.length > 0 ? secondaryPaneWidth / 2 : 0;
          const rightPaneWidth =
            rightSecondaryPaneWindows.length > 0 ? secondaryPaneWidth / 2 : 0;
          const centerPaneWidth =
            screenFrame.width - leftPaneWidth - rightPaneWidth;

          const leftPane = {
            ...screenFrame,
            width: leftPaneWidth,
          };
          const centerPane = {
            ...screenFrame,
            x: leftPane.x + leftPane.width,
            width: centerPaneWidth,
          };
          const rightPane = {
            ...screenFrame,
            x: centerPane.x + centerPane.width,
            width: rightPaneWidth,
          };

          return {
            ...bspWindowPanes(mainPaneWindows, centerPane, false),
            ...bspWindowPanes(leftSecondaryPaneWindows, leftPane, true),
            ...bspWindowPanes(rightSecondaryPaneWindows, rightPane, true),
          };
        }
      }
    },
  };
}
