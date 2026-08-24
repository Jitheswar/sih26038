# Screening demo UI

`ScreeningApp.m` is an App Designer-compatible MATLAB class that creates the UI with `uifigure`, `uigridlayout`, and `uiaxes`.

A binary `.mlapp` file was not generated because the repository is built and tested headlessly with `matlab -batch`.

The class keeps callbacks thin: `app.runScreeningCase` owns orchestration and `report.generate` owns report export.

The UI is a screening aid and research prototype, not a medical device or a clinical diagnosis.

## Layout

The window is a header, a left rail, and a workspace.

The header carries the two facts a judge asks about first: the frozen operating point with its freeze date, and that the sealed external set has not been opened.

The rail holds the case, the two actions, run status, the frozen model paths, the headline validation numbers, and a per-stage pipeline list.

The workspace leads with a verdict strip, because the decision is the most consequential output of the pipeline and the previous layout buried it in a column of identical grey lines.

Below that are the four image panels and the evidence and rule-trace panels.

Every colour comes from `ScreeningApp.palette`, and the ground is dark on purpose: fundus images are dark, warm and low-contrast, and they read better against a neutral dark surface than against white.

## Numbers on screen

The validation sensitivity and specificity in the rail, and the operating point in the header, are read from `config/default.json`.

Nothing is typed in, so the card cannot drift away from the frozen operating point it claims to describe.

The calibrated referable probability is shown as a percentage to one decimal place rather than six, which implied a precision the calibration set does not support.

The pipeline stage marks are set from the returned result, not assumed, so a case stopped by the quality gate really does show the later stages as unlit.

## Animation

Results are revealed rather than snapped in: stages light in pipeline order, the four images fade in staggered, and the calibrated risk counts up to its value.

All of it runs after inference returns.

MATLAB is single threaded and the pipeline call never yields to the event loop, so nothing driven from the class could animate during the compute itself.

That is what the indeterminate `uiprogressdlg` is for: a `uifigure` is drawn by a separate front end, so its bar keeps moving while MATLAB is blocked.

A failed reveal is caught and the result snaps to its final state, and `app.AnimationsEnabled = false` disables the reveals entirely.

## Keyboard

Enter runs the current case.
