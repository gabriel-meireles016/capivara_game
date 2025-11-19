#imports necessários
from sqlalchemy import create_engine
from sqlalchemy.ext.automap import automap_base
from sqlalchemy.orm import Session


#Essa url aqui recomendo fazer com o chatgpt pq cada um instalou de um jeito
DATABASE_URL = "postgresql+psycopg2://postgres:12345@localhost:5432/domino_db"

#Dá a url pro sqlalchemy procurar
engine = create_engine(DATABASE_URL)

#Automap = mapear nosso bd e carregar as tabelas automaticamente
Base = automap_base()
Base.prepare(autoload_with=engine)


session = Session(engine)

#Trás as tabelas mapeadas pra gente conseguir mexer aqui mesmo
tables = Base.classes
