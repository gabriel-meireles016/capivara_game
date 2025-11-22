from sqlalchemy import text, create_engine

DATABASE_URL = "postgresql+psycopg2://postgres:12345@localhost:5432/domino_chat"

engine = create_engine(DATABASE_URL)

with open("script.sql", "r", encoding="utf8") as f:
    sql = f.read()

with engine.connect() as conn:
    conn.execute(text(sql))
    conn.commit()

print("Banco instalado com sucesso!")
