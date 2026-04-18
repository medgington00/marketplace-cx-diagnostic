import duckdb
import os

DB_PATH = "data/cx_diagnostic.duckdb"
DATA_DIR = "data"

con = duckdb.connect(DB_PATH)

tables = {
    "customers":          "customers.csv",
    "orders":             "orders.csv",
    "order_items":        "order_items.csv",
    "products":           "products.csv",
    "product_categories": "product_categories.csv",
    "sellers":            "sellers.csv",
    "payments":           "payments.csv",
    "reviews":            "reviews.csv",
    "geolocation":        "geolocation.csv",
}

for table_name, filename in tables.items():
    filepath = os.path.join(DATA_DIR, filename)
    con.execute(f"""
        CREATE OR REPLACE TABLE {table_name} AS
        SELECT * FROM read_csv_auto('{filepath}', header=true)
    """)
    count = con.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()[0]
    print(f"  {table_name:<22} {count:>10,} rows")

con.close()
print("\nDatabase written to data/cx_diagnostic.duckdb")