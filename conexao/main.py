import sys
import random
from sqlalchemy import create_engine, text
from sqlalchemy.ext.automap import automap_base
from sqlalchemy.orm import Session

DATABASE_URL = "postgresql+psycopg2://postgres:1234@localhost:5432/domino_chat"

# Conexão e mapeamento automático
engine = create_engine(DATABASE_URL)
Base = automap_base()
Base.prepare(autoload_with=engine)

session = Session(engine)
tables = Base.classes

# Mapear tabelas - usar os nomes exatos do banco
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
        print(f"ID: {u.idusuario} | Nome: {u.nome}")
    print()

def listar_partidas():
    partidas = session.query(Partida).all()
    print("\n=== Partidas ===")
    for p in partidas:
        vencedor = p.idjogadorvencedor or p.idduplavencedora
        print(f"Partida {p.idpartida} | Início: {p.datahorainicio} | Fim: {p.datahorafim} | Vencedor: {vencedor}")
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
    session.flush()  # Para obter o ID antes do commit
    print(f"Partida criada: {partida.idpartida}\n")

    # Adicionar jogadores
    print("IDs dos jogadores (ex: 1,2,3,4):")
    ids = [int(x.strip()) for x in input().split(',')]
    pos = 1
    
    for uid in ids:
        pu = PartidaUsuario(
            idpartida=partida.idpartida,
            idusuario=uid,
            iddupla=None,
            posicaomesa=pos
        )
        session.add(pu)
        pos += 1
    
    # Criar duplas se houver 4 jogadores
    if len(ids) == 4:
        duplas_ids = []
        for i in range(2):
            nomedupla = input(f"Nome da dupla {i+1}: ")
            dupla = Dupla(idpartida=partida.idpartida, nomedupla=nomedupla, pontuacaototal=0)
            session.add(dupla)
            session.flush()
            duplas_ids.append(dupla.iddupla)
        
        # Associar jogadores às duplas
        for idx, uid in enumerate(ids):
            pj = session.query(PartidaUsuario).filter_by(
                idpartida=partida.idpartida,
                idusuario=uid
            ).first()
            pj.iddupla = duplas_ids[0] if idx < 2 else duplas_ids[1]
    
    session.commit()
    return partida.idpartida

# ========================= PEÇAS =========================
def distribuir_pecas(idpartida):
    print("Distribuindo peças...")

    # Limpar peças antigas
    session.query(MaoPartida).filter_by(idpartida=idpartida).delete()
    session.commit()

    pecas = session.query(Peca).all()
    idspecas = [p.idpeca for p in pecas]
    random.shuffle(idspecas)

    jogadores = session.query(PartidaUsuario).filter_by(idpartida=idpartida).all()
    mao = 7 if len(jogadores) <= 2 else 5
    idx = 0

    for j in jogadores:
        for _ in range(mao):
            mp = MaoPartida(
                idpartida=idpartida,
                idpeca=idspecas[idx],
                idusuario=j.idusuario,
                statuspeca='em_mao'
            )
            session.add(mp)
            idx += 1

    # Restante das peças no monte
    for i in range(idx, len(idspecas)):
        mp = MaoPartida(
            idpartida=idpartida, 
            idpeca=idspecas[i], 
            idusuario=None,
            statuspeca='no_monte'
        )
        session.add(mp)

    session.commit()
    print("Peças distribuídas!\n")

# ========================= MOVIMENTOS =========================
def comprar_peca(idpartida):
    user = int(input("Jogador: "))
    try:
        # CORREÇÃO: Usar text() para chamar procedures
        session.execute(text(f"CALL ComprarPecaDoMonte({idpartida}, {user})"))
        session.commit()
        print("Peça comprada com sucesso!")
    except Exception as e:
        print(f"Erro ao comprar peça: {e}")
        session.rollback()

def jogar_peca(idpartida):
    user = int(input("Jogador: "))
    peca = int(input("ID da peça: "))
    lado = input("Extremidade (esquerda/direita): ")
    valor = int(input("Valor da extremidade: "))
    try:
        # CORREÇÃO: Usar text() e nomes corretos dos parâmetros
        session.execute(text(f"CALL ValidarJogada({idpartida}, {user}, {peca}, '{lado}', {valor})"))
        session.commit()
        print("Jogada realizada!")
    except Exception as e:
        print(f"Erro na jogada: {e}")
        session.rollback()

def mostrar_mao_jogador():
    idpartida = int(input("ID da partida: "))
    idusuario = int(input("ID do jogador: "))
    
    pecas_mao = session.query(MaoPartida, Peca).join(
        Peca, MaoPartida.idpeca == Peca.idpeca
    ).filter(
        MaoPartida.idpartida == idpartida,
        MaoPartida.idusuario == idusuario,
        MaoPartida.statuspeca == 'em_mao'
    ).all()
    
    print(f"\n=== Mão do Jogador {idusuario} (Partida {idpartida}) ===")
    for mao, peca in pecas_mao:
        print(f"Peça ID: {peca.idpeca} | Lados: [{peca.ladoa}-{peca.ladob}] | Pontos: {peca.pontospeca}")
    print(f"Total de peças: {len(pecas_mao)}\n")

# ========================= RANKING / HISTÓRICO =========================
def ranking():
    try:
        rows = session.execute(text("SELECT * FROM RankingUsuarios")).fetchall()
        print("\n=== Ranking ===")
        for r in rows:
            print(f"ID: {r[0]} | Nome: {r[1]} | Partidas: {r[2]} | Vitórias: {r[3]} | %: {r[4]} | Pontos: {r[5]}")
        print()
    except Exception as e:
        print(f"Erro ao carregar ranking: {e}")

def historico():
    try:
        rows = session.execute(text("SELECT * FROM PartidasDetalhadas")).fetchall()
        print("\n=== Histórico ===")
        for r in rows:
            print(f"Partida {r[0]} | Início: {r[1]} | Término: {r[2]} | Modo: {r[3]}")
        print()
    except Exception as e:
        print(f"Erro ao carregar histórico: {e}")

# ========================= LÓGICA DO JOGO INTERATIVO =========================

def obter_extremidades_partida(idpartida):
    """Obtém os valores atuais das extremidades da partida"""
    partida = session.query(Partida).filter_by(idpartida=idpartida).first()
    return partida.valorextesquerda, partida.valorextdireita

def mostrar_mesa(idpartida):
    """Mostra o estado atual da mesa"""
    partida = session.query(Partida).filter_by(idpartida=idpartida).first()
    ext_esq, ext_dir = partida.valorextesquerda, partida.valorextdireita
    
    print(f"\n=== MESA (Partida {idpartida}) ===")
    print(f"Extremidade ESQUERDA: {ext_esq}")
    print(f"Extremidade DIREITA: {ext_dir}")
    
    # Mostrar peças já jogadas
    pecas_jogadas = session.query(Movimentacao, Peca).join(
        Peca, Movimentacao.idpecajogada == Peca.idpeca
    ).filter(
        Movimentacao.idpartida == idpartida,
        Movimentacao.tipoacao == 'jogada'
    ).order_by(Movimentacao.ordemacao).all()
    
    if pecas_jogadas:
        print("Peças jogadas:", end=" ")
        for mov, peca in pecas_jogadas:
            print(f"[{peca.ladoa}-{peca.ladob}]", end=" ")
        print()

def mostrar_estado_jogador(idpartida, idusuario):
    """Mostra a mão do jogador e jogadas possíveis"""
    usuario = session.query(Usuario).filter_by(idusuario=idusuario).first()
    print(f"\n--- Vez de: {usuario.nome} (ID: {idusuario}) ---")
    
    # Mostrar mão do jogador
    pecas_mao = session.query(MaoPartida, Peca).join(
        Peca, MaoPartida.idpeca == Peca.idpeca
    ).filter(
        MaoPartida.idpartida == idpartida,
        MaoPartida.idusuario == idusuario,
        MaoPartida.statuspeca == 'em_mao'
    ).all()
    
    print("Sua mão:")
    for i, (mao, peca) in enumerate(pecas_mao, 1):
        print(f"  {i}. Peça [{peca.ladoa}-{peca.ladob}] (ID: {peca.idpeca}, Pontos: {peca.pontospeca})")
    
    # Mostrar jogadas possíveis
    jogadas_validas = obter_jogadas_validas(idpartida, idusuario)
    if jogadas_validas:
        print("\nJogadas possíveis:")
        for i, peca in enumerate(jogadas_validas, 1):
            ext_esq, ext_dir = obter_extremidades_partida(idpartida)
            opcoes = []
            if peca.ladoa == ext_esq or peca.ladob == ext_esq:
                opcoes.append("ESQUERDA")
            if peca.ladoa == ext_dir or peca.ladob == ext_dir:
                opcoes.append("DIREITA")
            print(f"  {i}. Peça [{peca.ladoa}-{peca.ladob}] (ID: {peca.idpeca}) → Encaxa em: {', '.join(opcoes)}")
    else:
        print("\nNenhuma jogada possível nas extremidades atuais")

def obter_jogadas_validas(idpartida, idusuario):
    """Retorna lista de peças que podem ser jogadas pelo usuário"""
    ext_esq, ext_dir = obter_extremidades_partida(idpartida)
    jogadas_validas = []
    
    pecas_mao = session.query(MaoPartida, Peca).join(
        Peca, MaoPartida.idpeca == Peca.idpeca
    ).filter(
        MaoPartida.idpartida == idpartida,
        MaoPartida.idusuario == idusuario,
        MaoPartida.statuspeca == 'em_mao'
    ).all()
    
    for mao, peca in pecas_mao:
        if (peca.ladoa == ext_esq or peca.ladob == ext_esq or 
            peca.ladoa == ext_dir or peca.ladob == ext_dir):
            jogadas_validas.append(peca)
    
    return jogadas_validas

def obter_proximo_jogador(idpartida, jogador_atual):
    """Obtém o próximo jogador na sequência anti-horária"""
    participantes = session.query(PartidaUsuario).filter_by(
        idpartida=idpartida
    ).order_by(PartidaUsuario.posicaomesa).all()
    
    pos_atual = None
    for i, p in enumerate(participantes):
        if p.idusuario == jogador_atual:
            pos_atual = i
            break
    
    if pos_atual is None:
        return None
    
    proxima_pos = (pos_atual + 1) % len(participantes)
    return participantes[proxima_pos].idusuario

def realizar_jogada_usuario(idpartida, idusuario):
    """Permite que o usuário realize uma jogada"""
    jogadas_validas = obter_jogadas_validas(idpartida, idusuario)
    
    if jogadas_validas:
        print("\nOpções:")
        print("1. Jogar peça")
        print("2. Comprar do monte")
        print("3. Passar a vez")
        
        opcao = input("Escolha uma opção (1-3): ").strip()
        
        if opcao == "1":
            # Jogar peça
            try:
                num_peca = int(input("Número da peça para jogar (ver lista acima): "))
                if 1 <= num_peca <= len(jogadas_validas):
                    peca_escolhida = jogadas_validas[num_peca - 1]
                    ext_esq, ext_dir = obter_extremidades_partida(idpartida)
                    
                    # Verificar em quais extremidades encaixa
                    encaixe_esq = peca_escolhida.ladoa == ext_esq or peca_escolhida.ladob == ext_esq
                    encaixe_dir = peca_escolhida.ladoa == ext_dir or peca_escolhida.ladob == ext_dir
                    
                    if encaixe_esq and encaixe_dir:
                        # Peça encaixa em ambos os lados, usuário escolhe
                        print(f"Peça [{peca_escolhida.ladoa}-{peca_escolhida.ladob}] encaixa em ambos os lados!")
                        extremidade = input("Escolha extremidade (E - Esquerda, D - Direita): ").strip().upper()
                        if extremidade == 'E':
                            extremidade = 'esquerda'
                            valor_extremidade = ext_esq
                        else:
                            extremidade = 'direita'
                            valor_extremidade = ext_dir
                    elif encaixe_esq:
                        extremidade = 'esquerda'
                        valor_extremidade = ext_esq
                    else:
                        extremidade = 'direita'
                        valor_extremidade = ext_dir
                    
                    # Realizar jogada
                    session.execute(text(
                        f"CALL ValidarJogada({idpartida}, {idusuario}, {peca_escolhida.idpeca}, '{extremidade}', {valor_extremidade})"
                    ))
                    
                    # Atualizar extremidades na partida
                    partida = session.query(Partida).filter_by(idpartida=idpartida).first()
                    if extremidade == 'esquerda':
                        # Determinar novo valor da extremidade esquerda
                        if peca_escolhida.ladoa == ext_esq:
                            novo_valor = peca_escolhida.ladob
                        else:
                            novo_valor = peca_escolhida.ladoa
                        partida.valorextesquerda = novo_valor
                    else:
                        # Determinar novo valor da extremidade direita
                        if peca_escolhida.ladoa == ext_dir:
                            novo_valor = peca_escolhida.ladob
                        else:
                            novo_valor = peca_escolhida.ladoa
                        partida.valorextdireita = novo_valor
                    
                    session.commit()
                    print(f"Peça [{peca_escolhida.ladoa}-{peca_escolhida.ladob}] jogada na extremidade {extremidade.upper()}!")
                    return True
                else:
                    print("Número de peça inválido!")
                    return False
            except ValueError:
                print("Entrada inválida!")
                return False
                
        elif opcao == "2":
            # Comprar do monte
            try:
                session.execute(text(f"CALL ComprarPecaDoMonte({idpartida}, {idusuario})"))
                session.commit()
                print("Peça comprada do monte!")
                return True
            except Exception as e:
                print(f"Erro ao comprar peça: {e}")
                session.rollback()
                return False
                
        elif opcao == "3":
            # Passar a vez
            print("Você passou a vez.")
            # Registrar passada no histórico
            ordem = session.query(Movimentacao).filter_by(idpartida=idpartida).count() + 1
            nova_mov = Movimentacao(
                idpartida=idpartida,
                idusuario=idusuario,
                ordemacao=ordem,
                tipoacao='passou',
                idpecajogada=None,
                extremidademesa=None
            )
            session.add(nova_mov)
            session.commit()
            return True
        else:
            print("Opção inválida!")
            return False
    else:
        # Nenhuma jogada possível, apenas comprar ou passar
        print("\nNenhuma jogada possível nas extremidades atuais")
        print("Opções:")
        print("1. Comprar do monte")
        print("2. Passar a vez")
        
        opcao = input("Escolha uma opção (1-2): ").strip()
        
        if opcao == "1":
            try:
                session.execute(text(f"CALL ComprarPecaDoMonte({idpartida}, {idusuario})"))
                session.commit()
                print("Peça comprada do monte!")
                return True
            except Exception as e:
                print(f"Erro ao comprar peça: {e}")
                session.rollback()
                return False
        elif opcao == "2":
            print("Você passou a vez.")
            ordem = session.query(Movimentacao).filter_by(idpartida=idpartida).count() + 1
            nova_mov = Movimentacao(
                idpartida=idpartida,
                idusuario=idusuario,
                ordemacao=ordem,
                tipoacao='passou',
                idpecajogada=None,
                extremidademesa=None
            )
            session.add(nova_mov)
            session.commit()
            return True
        else:
            print("Opção inválida!")
            return False

def verificar_jogador_bateu(idpartida, idusuario):
    """Verifica se jogador bateu (ficou sem peças)"""
    pecas_mao = session.query(MaoPartida).filter_by(
        idpartida=idpartida,
        idusuario=idusuario,
        statuspeca='em_mao'
    ).count()
    
    return pecas_mao == 0

def verificar_jogo_trancado(idpartida):
    """Verifica se o jogo está trancado"""
    ext_esq, ext_dir = obter_extremidades_partida(idpartida)
    
    participantes = session.query(PartidaUsuario).filter_by(idpartida=idpartida).all()
    
    for participante in participantes:
        # Verificar se jogador tem peças válidas
        jogadas_validas = obter_jogadas_validas(idpartida, participante.idusuario)
        if jogadas_validas:
            return False
    
    # Verificar se ainda há peças no monte
    pecas_monte = session.query(MaoPartida).filter_by(
        idpartida=idpartida,
        statuspeca='no_monte'
    ).count()
    
    return pecas_monte == 0  # Jogo trancado apenas se monte também estiver vazio

def calcular_pontuacao_trancamento(idpartida):
    """Calcula pontuação quando jogo está trancado"""
    participantes = session.query(PartidaUsuario).filter_by(idpartida=idpartida).all()
    
    # Para jogo individual (2-3 jogadores)
    if all(p.iddupla is None for p in participantes):
        pontuacoes = []
        for p in participantes:
            pontos = session.query(text('SUM(peca.pontospeca)')).select_from(MaoPartida).join(
                Peca, MaoPartida.idpeca == Peca.idpeca
            ).filter(
                MaoPartida.idpartida == idpartida,
                MaoPartida.idusuario == p.idusuario,
                MaoPartida.statuspeca == 'em_mao'
            ).scalar() or 0
            pontuacoes.append((p.idusuario, pontos))
        
        # Vencedor é quem tem menos pontos
        pontuacoes.sort(key=lambda x: x[1])
        return pontuacoes[0][0], pontuacoes[0][1]  # id_vencedor, pontos
    
    # Para jogo em duplas (implementação básica)
    else:
        # Lógica simplificada para duplas
        duplas = {}
        for p in participantes:
            if p.iddupla not in duplas:
                duplas[p.iddupla] = 0
            
            pontos = session.query(text('SUM(peca.pontospeca)')).select_from(MaoPartida).join(
                Peca, MaoPartida.idpeca == Peca.idpeca
            ).filter(
                MaoPartida.idpartida == idpartida,
                MaoPartida.idusuario == p.idusuario,
                MaoPartida.statuspeca == 'em_mao'
            ).scalar() or 0
            duplas[p.iddupla] += pontos
        
        # Dupla vencedora é a com menos pontos
        id_dupla_vencedora = min(duplas, key=duplas.get)
        return None, id_dupla_vencedora, duplas[id_dupla_vencedora]

def finalizar_partida(idpartida, motivo, idvencedor=None, idduplavencedora=None):
    """Finaliza a partida e calcula pontuação"""
    partida = session.query(Partida).filter_by(idpartida=idpartida).first()
    
    partida.datahorafim = text("CURRENT_TIMESTAMP")
    partida.modotermino = motivo
    
    if idvencedor:
        partida.idjogadorvencedor = idvencedor
    elif idduplavencedora:
        partida.idduplavencedora = idduplavencedora
    
    session.commit()
    print(f"\n=== PARTIDA FINALIZADA ===")
    print(f"Motivo: {motivo}")
    if idvencedor:
        usuario = session.query(Usuario).filter_by(idusuario=idvencedor).first()
        print(f"Vencedor: {usuario.nome}")
    elif idduplavencedora:
        dupla = session.query(Dupla).filter_by(iddupla=idduplavencedora).first()
        print(f"Dupla vencedora: {dupla.nomedupla}")
    print(f"Pontos da partida: {partida.pontosdapartida}")

def jogar_partida_interativa(idpartida):
    """Loop principal do jogo interativo"""
    print(f"\n=== INICIANDO PARTIDA {idpartida} ===")
    
    # Distribuir peças
    distribuir_pecas(idpartida)
    
    # Encontrar jogador com peça 6-6 para começar
    peca_66 = session.query(Peca).filter_by(ladoa=6, ladob=6).first()
    mao_66 = session.query(MaoPartida).filter_by(
        idpartida=idpartida, 
        idpeca=peca_66.idpeca,
        statuspeca='em_mao'
    ).first()
    
    if mao_66:
        jogador_atual = mao_66.idusuario
        usuario = session.query(Usuario).filter_by(idusuario=jogador_atual).first()
        print(f"{usuario.nome} tem a peça 6-6 e inicia a partida!")
        
        # Jogador joga a peça 6-6
        input("Pressione Enter para jogar a peça 6-6...")
        session.execute(text(
            f"CALL ValidarJogada({idpartida}, {jogador_atual}, {peca_66.idpeca}, 'centro', 6)"
        ))
        
        # Atualizar extremidades iniciais
        partida = session.query(Partida).filter_by(idpartida=idpartida).first()
        partida.valorextesquerda = 6
        partida.valorextdireita = 6
        session.commit()
        
    else:
        # Começar com jogador aleatório se ninguém tem 6-6
        participantes = session.query(PartidaUsuario).filter_by(idpartida=idpartida).all()
        jogador_atual = random.choice(participantes).idusuario
        usuario = session.query(Usuario).filter_by(idusuario=jogador_atual).first()
        print(f"Ninguém tem 6-6. {usuario.nome} inicia a partida!")
    
    # Loop principal do jogo
    turno = 1
    while True:
        print(f"\n{'='*50}")
        print(f"TURNO {turno}")
        print(f"{'='*50}")
        
        usuario_atual = session.query(Usuario).filter_by(idusuario=jogador_atual).first()
        print(f"Vez de: {usuario_atual.nome}")
        
        # Mostrar estado atual
        mostrar_mesa(idpartida)
        mostrar_estado_jogador(idpartida, jogador_atual)
        
        # Verificar se jogador atual bateu
        if verificar_jogador_bateu(idpartida, jogador_atual):
            print(f"\n🎉 {usuario_atual.nome} BATEU O JOGO!")
            finalizar_partida(idpartida, 'bater', idvencedor=jogador_atual)
            break
        
        # Verificar se jogo está trancado
        if verificar_jogo_trancado(idpartida):
            print(f"\n🔒 JOGO TRANCADO!")
            if len(session.query(PartidaUsuario).filter_by(idpartida=idpartida).all()) <= 3:
                id_vencedor, pontos = calcular_pontuacao_trancamento(idpartida)
                finalizar_partida(idpartida, 'trancado', idvencedor=id_vencedor)
            else:
                id_vencedor, id_dupla_vencedora, pontos = calcular_pontuacao_trancamento(idpartida)
                finalizar_partida(idpartida, 'trancado', idduplavencedora=id_dupla_vencedora)
            break
        
        # Aguardar jogada do usuário
        input("\nPressione Enter para fazer sua jogada...")
        jogada_realizada = realizar_jogada_usuario(idpartida, jogador_atual)
        
        if jogada_realizada:
            # Avançar para próximo jogador
            jogador_anterior = jogador_atual
            jogador_atual = obter_proximo_jogador(idpartida, jogador_atual)
            turno += 1
        else:
            print("Jogada inválida, tente novamente.")

# ========================= ATUALIZAR MENU =========================

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
10. Mostrar mão
11. Jogar partida interativa  # NOVA OPÇÃO
0. Sair
        """)
        c = input("Opção: ")

        if c == "1": listar_usuarios()
        elif c == "2": criar_jogador()
        elif c == "3": iniciar_partida()
        elif c == "4": 
            pid = int(input("ID da partida: "))
            distribuir_pecas(pid)
        elif c == "5": 
            pid = int(input("ID da partida: "))
            comprar_peca(pid)
        elif c == "6": 
            pid = int(input("ID da partida: "))
            jogar_peca(pid)
        elif c == "7": listar_partidas()
        elif c == "8": ranking()
        elif c == "9": historico()
        elif c == "10": mostrar_mao_jogador()
        elif c == "11":  # NOVA OPÇÃO INTERATIVA
            pid = int(input("ID da partida: "))
            jogar_partida_interativa(pid)
        elif c == "0": 
            session.close()
            sys.exit()
        else: print("Opção inválida.\n")

if __name__ == "__main__":
    menu()