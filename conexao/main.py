import sys
import random
from sqlalchemy import create_engine
from sqlalchemy.ext.automap import automap_base
from sqlalchemy.orm import Session

DATABASE_URL = "postgresql+psycopg2://postgres:12345@localhost:5432/domino_chat"

# Conexão e mapeamento automático
engine = create_engine(DATABASE_URL)
Base = automap_base()
Base.prepare(autoload_with=engine)

session = Session(engine)
tables = Base.classes

# Mapear tabelas com os novos nomes em snake_case
Usuario = tables.usuario
Dupla = tables.dupla
Partida = tables.partida
Peca = tables.peca
MaoPartida = tables.maopartida
Movimentacao = tables.movimentacao
PartidaUsuario = tables.partidausuario

# ========================= UTILITÁRIOS =========================
def listar_usuarios():
    usuarios = session.query(Usuario).all()
    print("\n=== Usuários ===")
    for u in usuarios:
        print(f"ID: {u.id_usuario} | Nome: {u.nome}")
    print()

def listar_partidas():
    partidas = session.query(Partida).all()
    print("\n=== Partidas ===")
    for p in partidas:
        vencedor = p.id_jogador_vencedor or p.id_dupla_vencedora
        print(f"Partida {p.id_partida} | Início: {p.datahora_inicio} | Fim: {p.datahora_fim} | Vencedor: {vencedor}")
    print()

def criar_jogador():
    nome = input("Nome: ")
    novo = Usuario(nome=nome)
    session.add(novo)
    session.commit()
    print("Usuário criado!\n")

# ========================= PARTIDA =========================
def iniciar_partida():
    print("\n=== Nova partida ===")
    partida = Partida()
    session.add(partida)
    session.commit()
    print(f"Partida criada: {partida.id_partida}\n")

    # Adicionar jogadores
    print("IDs dos jogadores (ex: 1,2,3,4):")
    ids = [int(x.strip()) for x in input().split(',')]
    pos = 1
    for uid in ids:
        pu = PartidaUsuario(
            id_partida=partida.id_partida,
            id_usuario=uid,
            id_dupla=None,
            posicao_mesa=pos
        )
        session.add(pu)
        pos += 1
    session.commit()

    # Criar duplas se houver 4 jogadores
    if len(ids) == 4:
        for i in range(2):
            nome_dupla = input(f"Nome da dupla {i+1}: ")
            dupla = Dupla(id_partida=partida.id_partida, nome_dupla=nome_dupla)
            session.add(dupla)
            session.commit()
            for j in range(i*2, i*2+2):
                pj = session.query(PartidaUsuario).filter_by(
                    id_partida=partida.id_partida,
                    id_usuario=ids[j]
                ).first()
                pj.id_dupla = dupla.id_dupla
                session.add(pj)
        session.commit()

    return partida.id_partida

# ========================= PEÇAS =========================
def distribuir_pecas(id_partida):
    print("Distribuindo peças...")

    # Limpar peças antigas
    session.query(MaoPartida).filter_by(id_partida=id_partida).delete()
    session.commit()

    pecas = session.query(Peca).all()
    ids_pecas = [p.id_peca for p in pecas]
    random.shuffle(ids_pecas)

    jogadores = session.query(PartidaUsuario).filter_by(id_partida=id_partida).all()
    mao = 7 if len(jogadores) <= 2 else 5
    idx = 0

    for j in jogadores:
        for _ in range(mao):
            mp = MaoPartida(
                id_partida=id_partida,
                id_peca=ids_pecas[idx],
                id_usuario=j.id_usuario,
                status_peca='em_mao'
            )
            session.add(mp)
            idx += 1

    # Restante das peças no monte
    for i in range(idx, len(ids_pecas)):
        mp = MaoPartida(id_partida=id_partida, id_peca=ids_pecas[i], status_peca='no_monte')
        session.add(mp)

    session.commit()
    print("Peças distribuídas!\n")

# ========================= MOVIMENTOS =========================
def comprar_peca(id_partida):
    user = int(input("Jogador: "))
    session.execute(f"CALL comprar_peca_do_monte({id_partida}, {user});")
    session.commit()

def jogar_peca(id_partida):
    user = int(input("Jogador: "))
    peca = int(input("ID da peça: "))
    lado = input("Extremidade (esq/dir): ")
    valor = int(input("Valor da extremidade: "))
    session.execute(f"CALL validar_jogada({id_partida}, {user}, {peca}, '{lado}', {valor});")
    session.commit()

# ========================= RANKING / HISTÓRICO =========================
def ranking():
    rows = session.execute("SELECT * FROM ranking_usuarios").fetchall()
    print("\n=== Ranking ===")
    for r in rows:
        print(r)
    print()

def historico():
    rows = session.execute("SELECT * FROM partidas_detalhadas").fetchall()
    print("\n=== Histórico ===")
    for r in rows:
        print(r)
    print()

# ========================= MENU =========================
def menu():
    while True:
        print("""
================ DOMINÓ CLI ================
1. Listar usuários
2. Criar jogador
3. Iniciar partida
4. Distribuir peças
5. Comprar peça
6. Jogar peça
7. Listar partidas
8. Ranking
9. Histórico
0. Sair
        """)
        c = input("Opção: ")

        if c == "1": listar_usuarios()
        elif c == "2": criar_jogador()
        elif c == "3": iniciar_partida()
        elif c == "4": distribuir_pecas(int(input("ID da partida: ")))
        elif c == "5": comprar_peca(int(input("ID da partida: ")))
        elif c == "6": jogar_peca(int(input("ID da partida: ")))
        elif c == "7": listar_partidas()
        elif c == "8": ranking()
        elif c == "9": historico()
        elif c == "0": sys.exit()
        else: print("Opção inválida.\n")

if __name__ == "__main__":
    menu()
