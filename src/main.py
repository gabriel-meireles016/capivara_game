from conexao.database import session, tables
from conexao.query import mostrar_usuarios

def menu_principal():
    print("==== CAPIVARA GAME APRESENTA: DOMINÓ ====")
    print("1. Listar usuários cadastrados")
    print("2. Iniciar partida")
    print("3. Ranking")
    print("4. Histórico de partidas")
    print("5. Sair")

    return input("Escolha uma opção: ")

def iniciar_partida():
    print("==== NOVA SESSÃO ====")

    # jogadores
    id_jogadores = input("Insira os jogadores: ").split(",")
    id_jogadores = [int(id.strip()) for id in id_jogadores]
 
    if len(id_jogadores) not in [2, 3, 4]:
        print("Número inválido de jogadores. Devem ser 2, 3 ou 4!")
        return
    
    # cria sessão de jogo
    nova_sessao = tables.sessaojogo(ID_TipoJogo = 1)
    session.add(nova_sessao)
    session.commit()

    print(f"Sessão {nova_sessao.ID_SessaoJogo} criada com sucesso!")
    return nova_sessao.ID_SessaoJogo

def historico_partidas():
    print("\n==== HISTÓRICO DAS PARTIDAS ====")
    sessoes = session.execute("SELECT * FROM DetalhesSessoes").fetchall()

    for sessao in sessoes:
        print(f"\nSessão {sessao.id_sessaojogo}: {sessao.nomejogo}")
        print(f"\nInício: {sessao.datahorainicio}")
        print(f"\nFim: {sessao.datahorafim}")
        print(f"\nPartidas: {sessao.totalpartidas} ({sessao.partidasfinalizadas} finalizadas)")
        print(f"\nDuplas: {sessao.nomedupla1} vs {sessao.nomedupla2}")
        print(f"\nPontuação: {sessao.pontuacaodupla1} - {sessao.pontuacaodupla2}")
        print()

def main():
    while True:
        opcao = menu_principal()

        if opcao == 1:
            iniciar_partida()
        elif opcao == 2:
            historico_partidas()
        elif opcao == 3:
            print("Obrigado por jogar. Volte sempre!")
            break
        else:
            print("Opção inválida.")