# Isolated Product Testing

Blind testing is meaningful only when the tester cannot inspect source, plans, diffs,
or implementation discussion. Store holdout scenarios outside the repository, build a
candidate artifact, and prepare a new workspace:

```bash
python3 scripts/prepare_product_test.py \
  --artifact /absolute/path/to/candidate \
  --holdout /absolute/path/to/private-holdout.md \
  --output /absolute/path/to/new-test-workspace
```

Start Claude Code inside that new directory with `--agent product-tester`. For full
automation, CI should create an equivalent artifact-only job and publish its structured
result. Never use a source-containing worktree as the blind environment.

Hardware tests should expose only a bounded test-control interface. GUI tests should
prefer a UI automation/computer-use interface. Neither tester needs a general-purpose
view of the development checkout.
