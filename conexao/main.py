import sys
from sqlalchemy import create_engine
from sqlalchemy.ext.automap import automap_base
from sqlalchemy.orm import Session
from sqlalchemy import text
import random

# ==============================
# CONFIGURAÇÃO DO BANCO
# ==============================
DATABASE_URL = "postgresql+psycopg2://postgres:12345@localhost:5432/domino_chat"

engine = create_engine(DATABASE_URL)
Base = automap_base()
Base.prepare(autoload_with=engine)

session = Session(engine)
tables = Base.classes

Usuario = tables.usuario
SessaoJogo = tables.sessaojogo
Dupla = tables.dupla
SessaoUsuario = tables.sessao_usuario
Partida = tables.partida
Peca = tables.peca
MaoPartida = tables.maopartida
Movimentacao = tables.movimentacao
TipoJogo = tables.tipojogo

# ============================================================
# FUNÇÕES DE LISTAGEM
# ============================================================

def listar_usuarios():
    usuarios = session.query(Usuario).all()
    print("\n=== Usuários ===")
    for u in usuarios:
        print(f"ID: {u.id_usuario} | Nome: {u.nome} | Email: {u.email}")
    print()


def listar_sessoes():
    sessoes = session.query(SessaoJogo).all()
    print("\n=== Sessões ===")
    for s in sessoes:
        print(f"Sessão {s.id_sessaojogo} | Início: {s.datahorainicio} | Fim: {s.datahorafim}")
    print()


def listar_partidas(id_sessao):
    partidas = session.query(Partida).filter_by(id_sessaojogo=id_sessao).all()
    print(f"\n=== Partidas da sessão {id_sessao} ===")
    for p in partidas:
        print(
            f"Partida {p.id_partida} | Inicio: {p.datahorainicio} | Fim: {p.datahorafim} | "
            f"Modo: {p.modotermino} | Jogador venceu: {p.id_jogadorvencedor} | Dupla venceu: {p.id_duplavencedora}"
        )
    print()


# ============================================================
# SESSÕES
# ============================================================

def iniciar_sessao():
    print("\n=== Criando Nova Sessão ===")

    jogos = session.query(TipoJogo).all()
    for j in jogos:
        print(f"{j.id_tipojogo} - {j.nomejogo} (alvo {j.pontuacaoalvo})")

    tipo = int(input("Tipo de jogo: "))

    nova = SessaoJogo(id_tipojogo=tipo)
    session.add(nova)
    session.commit()

    print(f"Sessão criada: {nova.id_sessaojogo}\n")
    return nova.id_sessaojogo


def adicionar_jogadores_sessao(id_sessao):
    print("IDs dos jogadores (ex: 1,2,3,4):")
    ids = [int(x.strip()) for x in input().split(',')]

    pos = 1
    for uid in ids:
        su = SessaoUsuario(
            id_sessaojogo=id_sessao,
            id_usuario=uid,
            posicaomesa=pos
        )
        session.add(su)
        pos += 1

    session.commit()
    print("Jogadores adicionados!\n")


# ============================================================
# DUPLAS
# ============================================================

def criar_duplas(id_sessao):
    print("\n=== Criando Duplas ===")

    jogadores = session.query(SessaoUsuario).filter_by(id_sessaojogo=id_sessao).all()

    if len(jogadores) not in (2, 4):
        print("Duplas só podem ser criadas para 2 ou 4 jogadores!")
        return

    nomes = []
    for i in range(1, 3):
        nome = input(f"Nome da dupla {i}: ")
        dupla = Dupla(id_sessaojogo=id_sessao, nomedupla=nome)
        session.add(dupla)
        session.commit()
        nomes.append(dupla.id_dupla)

    print("Agora associe jogadores às duplas:")
    for su in jogadores:
        user = session.query(Usuario).get(su.id_usuario)
        d = int(input(f"Jogador {user.nome} entra em qual dupla? ({nomes[0]}/{nomes[1]}): "))
        su.id_dupla = d

    session.commit()
    print("Duplas criadas e jogadores associados!\n")


# ============================================================
# PARTIDAS
# ============================================================

def iniciar_partida(id_sessao):
    print("\n=== Nova partida ===")

    jogadores = session.query(SessaoUsuario).filter_by(id_sessaojogo=id_sessao).all()
    for j in jogadores:
        u = session.query(Usuario).get(j.id_usuario)
        print(f"{u.id_usuario} - {u.nome}")

    ini = int(input("Quem inicia? "))

    p = Partida(id_sessaojogo=id_sessao, id_jogadoriniciou=ini)
    session.add(p)
    session.commit()

    print(f"Partida criada: {p.id_partida}\n")
    return p.id_partida


# ============================================================
# PEÇAS
# ============================================================

def distribuir_pecas(id_partida):
    print("\nDistribuindo peças...")

    # Limpa distribuições anteriores
    session.query(MaoPartida).filter_by(id_partida=id_partida).delete()
    session.commit()

    pecas_ids = [p.id_peca for p in session.query(Peca).all()]
    random.shuffle(pecas_ids)

    partida = session.query(Partida).get(id_partida)
    jogadores = session.query(SessaoUsuario).filter_by(id_sessaojogo=partida.id_sessaojogo).all()

    mao = 7 if len(jogadores) <= 2 else 5
    idx = 0

    for j in jogadores:
        for _ in range(mao):
            mp = MaoPartida(id_partida=id_partida, id_peca=pecas_ids[idx], id_usuario=j.id_usuario, statuspeca="em_mao")
            session.add(mp)
            idx += 1

    # Monte
    while idx < len(pecas_ids):
        mp = MaoPartida(id_partida=id_partida, id_peca=pecas_ids[idx], statuspeca="no_monte")
        session.add(mp)
        idx += 1

    session.commit()
    print("Peças distribuídas!\n")


# ============================================================
# MOVIMENTAÇÃO
# ============================================================

def comprar_peca(id_partida):
    user = int(input("Jogador: "))
    session.execute(text("CALL ComprarPecaDoMonte(:p,:u)"), {"p": id_partida, "u": user})
    session.commit()
    print("Peça comprada!\n")


def jogar_peca(id_partida):
    user = int(input("Jogador: "))
    peca = int(input("ID da peça: "))
    lado = input("Extremidade (esquerda/direita): ")
    valor = int(input("Valor da extremidade usada: "))

    session.execute(
        text("CALL ValidarJogada(:p,:u,:pc,:lado,:val)"),
        {"p": id_partida, "u": user, "pc": peca, "lado": lado, "val": valor}
    )
    session.commit()
    print("Jogada registrada!\n")


# ============================================================
# RANKING E HISTÓRICO
# ============================================================

def ranking():
    rows = session.execute(text("SELECT * FROM rankingusuarios")).fetchall()
    print("\n=== Ranking ===")
    for r in rows:
        print(r)
    print()


def historico():
    rows = session.execute(text("SELECT * FROM detalhessessoes")).fetchall()
    print("\n=== Histórico ===")
    for r in rows:
        print(r)
    print()


# ============================================================
# MENU
# ============================================================

def menu():
    while True:
        print("""
================ DOMINÓ CLI ================
1. Listar usuários
2. Criar sessão
3. Adicionar jogadores à sessão
4. Criar duplas
5. Listar sessões
6. Criar partida
7. Distribuir peças
8. Comprar peça
9. Jogar peça
10. Ranking
11. Histórico
0. Sair
        """)

        op = input("Opção: ")

        try:
            if op == "1": listar_usuarios()
            elif op == "2": iniciar_sessao()
            elif op == "3": adicionar_jogadores_sessao(int(input("Sessão: ")))
            elif op == "4": criar_duplas(int(input("Sessão: ")))
            elif op == "5": listar_sessoes()
            elif op == "6": iniciar_partida(int(input("Sessão: ")))
            elif op == "7": distribuir_pecas(int(input("Partida: ")))
            elif op == "8": comprar_peca(int(input("Partida: ")))
            elif op == "9": jogar_peca(int(input("Partida: ")))
            elif op == "10": ranking()
            elif op == "11": historico()
            elif op == "0": sys.exit()
            else:
                print("Opção inválida!\n")
        except Exception as e:
            print("\n[ERRO]", e, "\n")
            session.rollback()


if __name__ == "__main__":
    menu()
