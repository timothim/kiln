"""Distilled local classifiers for Kiln (M9.C).

Three components, each a thin wrapper over deterministic features +
scikit-learn where labelled data exists:

- ``quality``: text -> [0, 1] score. Trained on Opus-4.7 quality labels
  (1500 examples). TF-IDF + LogisticRegression. Artifact lives at
  ``artifacts/quality-classifier.pkl``.
- ``preference``: (text_a, text_b) -> ("A" | "B" | "tie", margin).
  Heuristic feature-based scorer; the Opus-labelled inputs that would let
  us train a real pairwise model were not recovered, so this milestone
  ships the heuristic and validates it against the recorded winners.
- ``style``: corpus -> {descriptors, distinctive_ngrams, markdown_card}.
  Deterministic TF-IDF + 6-axis stylometric heuristics; same recovery
  reason as ``preference``.

Each module exposes a ``score(...)`` function for inference. The
``train`` entry points (where applicable) are dev-time only — they are
invoked from ``scripts/distill/`` or by ``python -m kiln_trainer
classify --train …``. The shipped Kiln.app calls only ``score(...)`` at
runtime (no network, no MLX requirement)."""

from kiln_trainer.classifiers import preference, quality, style

__all__ = ["quality", "preference", "style"]
