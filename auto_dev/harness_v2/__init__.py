"""Deterministic lifecycle and provenance gates for the V2 supervisor.

This package is intentionally additive: the production queue runner remains
untouched until the V2 selftests and disposable E2E are approved.
"""

from .core import (
    BootstrapResult,
    IntegrationCoordinator,
    LifecycleController,
    Lifecycle,
    TaskState,
    V2StateStore,
    classify_failure,
    source_commit,
)

__all__ = [
    "BootstrapResult", "IntegrationCoordinator", "LifecycleController", "Lifecycle", "TaskState",
    "V2StateStore", "classify_failure", "source_commit",
]
