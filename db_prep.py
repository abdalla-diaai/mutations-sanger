import polars as ps
import sqlite3
import pandas as pd


# somatic mutations table
csv = ps.read_csv("db/mutations_all_latest.csv")
csv = csv.filter(ps.col("effect") != "intronic")
columns_to_keep = ["model_id", "gene_symbol", "ensembl_gene_id", "model_name", "cdna_mutation", "protein_mutation","type", "effect", "vaf", "data_type"]

csv = csv.select(columns_to_keep)

csv.write_database(
  "SomaticMutations",
  "sqlite:///db/ccle.db",
  if_table_exists = "replace",
  engine = "adbc",
)

# helper function to extract gene names from somatic mutations dataset
def get_column_values(df, column1):
  return (df[column1]).to_list()


gene_names = get_column_values(csv, "gene_symbol")

# convert to dataframe
g2t = ps.DataFrame(
  {
    "Gene": [x for x in gene_names],
  }
)

# write to sqlite3 database
g2t.write_database("Genes", "sqlite:///db/ccle.db", if_table_exists = "replace", engine="adbc")

# connect to dataset
con = sqlite3.connect("db/ccle.db")
# Optimize database
con.execute("PRAGMA synchronous = OFF;")
con.execute("PRAGMA journal_mode = MEMORY;")
con.execute("PRAGMA temp_store = MEMORY;")
# Perform ANALYZE to update statistics
con.execute("ANALYZE;")
# Perform VACUUM to reduce database size
con.execute("VACUUM;")
# Index columns
con.execute("CREATE INDEX ix_gt_gene ON Genes(Gene)")
con.execute("CREATE INDEX ix_mod_profile ON SomaticMutations(model_name)")

# Create views
con.execute(
  """
  CREATE VIEW view_unique_genes
  AS
    SELECT DISTINCT Gene FROM Genes ORDER BY Gene
  """
)

con.execute(
  """
  CREATE VIEW view_unique_cellLines
  AS
    SELECT DISTINCT model_name FROM SomaticMutations ORDER BY model_name
  """
)

con.close()

