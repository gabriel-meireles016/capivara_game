import sys
from sqlalchemy import create_engine
from sqlalchemy.ext.automap import automap_base
from sqlalchemy.orm import Session

DATABASE_URL = "postgresql+psycopg2://postgres:12345@localhost:5432/domino_chat"
engine = create_engine(DATABASE_URL)
Base = automap_base()
Base.prepare(autoload_with=engine)

session = Session(engine)
tables = Base.classes

Usuario = tables.usuario
Dupla = tables.dupla
Partida = tables.partida
Peca = tables.peca
MaoPartida = tables.maopartida
Movimentacao = tables.movimentacao
PartidaUsuario = tables.partidausuario