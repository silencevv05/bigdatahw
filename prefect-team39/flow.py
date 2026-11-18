"""Run the team39 Spark pipeline through Prefect."""
import fcntl
import subprocess
from pathlib import Path

from prefect import flow, task

ROOT = Path(__file__).resolve().parent


@task(name="Pipeline stage", persist_result=False, cache_policy=None)
def run_stage(stage: str) -> None:
    log_path = ROOT / "build" / f"{stage}.log"
    print(f"Starting {stage}. Log: {log_path}")

    with log_path.open("w") as log:
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/stage.sh"), stage],
            cwd=ROOT,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )

    output = log_path.read_text(errors="replace")
    print("\n".join(output.splitlines()[-50:]))
    result.check_returncode()
    print(f"Stage completed: {stage}")


@flow(name="hw_5-team39-orders", log_prints=True)
def orders_pipeline() -> None:
    run_stage.with_options(name="Check HDFS input")("check")
    run_stage.with_options(name="Spark on YARN")("spark")
    run_stage.with_options(name="Verify Hive results")("verify")
    print("HW5 PASS: all three stages completed")


if __name__ == "__main__":
    (ROOT / "build").mkdir(exist_ok=True)
    lock_path = Path.home() / "venvs/hw_5/pipeline.lock"
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        orders_pipeline()
