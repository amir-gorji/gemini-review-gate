# Calibration corpus

This directory is where a repository using the action keeps its `reject-*.diff` and `approve-*.diff` cases.
It is empty here on purpose: a case is a diff against the tree it was planted in, so the corpus belongs to the repository under review, not to the action.

Capture a case with `scripts/capture-case.sh`, replay the directory with `mode: calibrate`, and exclude it from the per-PR review.
The README at the root covers all three.
