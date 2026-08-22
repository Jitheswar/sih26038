# Screening demo UI

`ScreeningApp.m` is an App Designer-compatible MATLAB class that creates the UI with `uifigure`, `uigridlayout`, and `uiaxes`.

A binary `.mlapp` file was not generated because the repository is built and tested headlessly with `matlab -batch`.

The class keeps callbacks thin: `app.runScreeningCase` owns orchestration and `report.generate` owns report export.

The UI is a screening aid and research prototype, not a medical device or a clinical diagnosis.
