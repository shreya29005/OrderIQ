from pathlib import Path
import sys
import duckdb
import pandas as pd


PROCESSED_DIR = Path("data/processed")
ANALYSIS_DIR = Path("data/analysis")
ANALYSIS_DIR.mkdir(parents=True, exist_ok=True)


TABLE_FILES = {
    "dim_users": "dim_users.csv",
    "dim_restaurants": "dim_restaurants.csv",
    "fact_sessions": "fact_sessions.csv",
    "fact_search_events": "fact_search_events.csv",
    "fact_cart_events": "fact_cart_events.csv",
    "fact_orders": "fact_orders.csv",
    "fact_delivery_ops": "fact_delivery_ops.csv",
    "fact_refunds": "fact_refunds.csv",
    "fact_ratings": "fact_ratings.csv",
    "daily_marketplace_metrics": "daily_marketplace_metrics.csv",
}


def create_connection() -> duckdb.DuckDBPyConnection:
    """
    Create an in-memory DuckDB connection and register processed CSV files as SQL views.
    """
    con = duckdb.connect(database=":memory:")

    for table_name, filename in TABLE_FILES.items():
        csv_path = PROCESSED_DIR / filename

        if not csv_path.exists():
            raise FileNotFoundError(f"Missing required file: {csv_path}")

        # Use read_csv_auto so DuckDB infers types from the CSV.
        query = f"""
        CREATE OR REPLACE VIEW {table_name} AS
        SELECT *
        FROM read_csv_auto('{csv_path.as_posix()}', HEADER = TRUE);
        """

        con.execute(query)

    return con


def run_sql_file(sql_path: Path) -> pd.DataFrame:
    """
    Execute a SQL file against the registered processed tables.
    """
    if not sql_path.exists():
        raise FileNotFoundError(f"SQL file not found: {sql_path}")

    sql = sql_path.read_text(encoding="utf-8")

    if not sql.strip():
        raise ValueError(f"SQL file is empty: {sql_path}")

    con = create_connection()
    result_df = con.execute(sql).fetchdf()
    con.close()

    return result_df


def main():
    if len(sys.argv) != 2:
        print("Usage:")
        print("python src/sql_runner.py sql/<query_file>.sql")
        sys.exit(1)

    sql_path = Path(sys.argv[1])

    print(f"Running SQL file: {sql_path}")

    result_df = run_sql_file(sql_path)

    output_path = ANALYSIS_DIR / f"{sql_path.stem}.csv"
    result_df.to_csv(output_path, index=False)

    print("\nQuery executed successfully.")
    print(f"Rows returned: {len(result_df)}")
    print(f"Columns returned: {list(result_df.columns)}")
    print(f"Saved output: {output_path}")

    print("\nPreview:")
    print(result_df.head(10).to_string(index=False))


if __name__ == "__main__":
    main()