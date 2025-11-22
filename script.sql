-- =========================================================
-- TABELAS
-- =========================================================

CREATE TABLE Usuario (
    idUsuario    SERIAL PRIMARY KEY,
    nome          VARCHAR(255) NOT NULL,
    dataCadastro  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Peças do dominó (28 peças)
CREATE TABLE Peca (
    idPeca    SERIAL PRIMARY KEY,
    ladoA      INT NOT NULL CHECK (ladoA BETWEEN 0 AND 6),
    ladoB      INT NOT NULL CHECK (ladoB BETWEEN 0 AND 6),
    pontosPeca INT NOT NULL -- soma de ladoA + ladoB
);

-- Partida (uma partida dentro de uma sessao)
CREATE TABLE Partida (
    idPartida SERIAL PRIMARY KEY,
    idJogadorIniciou INT,                     -- usuario que iniciou (idUsuario) -- NULL possível
    idJogadorVencedor INT,                    -- quando jogo 2/3 players
    idDuplaVencedora INT, -- quando jogo 4 players
    idDuplaTrancou INT,   -- dupla que causou o trancamento (se aplicável)
    pontosDaPartida INT NOT NULL DEFAULT 0,    -- pontos ganhos nesta partida (para o vencedor: soma pontos dos adversários)
    modoTermino VARCHAR(20),                   -- 'bater' | 'trancado' | NULL
    valorExtEsquerda INT,                      -- registro das extremidades (ajuda nas funções)
    valorExtDireita INT,
    dataHoraInicio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dataHoraFim TIMESTAMP
);

-- Dupla: apenas usada quando sessão tem 4 jogadores
CREATE TABLE Dupla (
    idDupla INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    idPartida INT NOT NULL REFERENCES Partida(idPartida) ON DELETE CASCADE,
    nomeDupla VARCHAR(100) NOT NULL,
    pontuacaoTotal INT NOT NULL DEFAULT 0
);

ALTER TABLE Partida ADD FOREIGN KEY (idDuplaVencedora) REFERENCES Dupla(idDupla);
ALTER TABLE Partida ADD FOREIGN KEY (idDuplaTrancou) REFERENCES Dupla(idDupla);

-- Associação usuário-sessão (quem participa de qual sessão; se em dupla, idDupla aponta)
CREATE TABLE PartidaUsuario (
    idPartida INT NOT NULL REFERENCES Partida(idPartida) ON DELETE CASCADE,
    idUsuario    INT NOT NULL REFERENCES Usuario(idUsuario) ON DELETE CASCADE,
    idDupla      INT REFERENCES Dupla(idDupla),
    posicaoMesa   INT NOT NULL, -- 1..4
    PRIMARY KEY (idPartida, idUsuario)
);

-- MaoPartida: estado das peças em uma partida (quem tem, se está no monte, etc.)
CREATE TABLE MaoPartida (
    idMaoPartida SERIAL PRIMARY KEY,
    idPartida INT NOT NULL REFERENCES Partida(idPartida) ON DELETE CASCADE,
    idPeca INT NOT NULL REFERENCES Peca(idPeca),
    idUsuario INT, -- NULL se a peça estiver no monte ou jogada
    statusPeca VARCHAR(20) NOT NULL CHECK (statusPeca IN ('no_monte','em_mao','jogada')),
    CONSTRAINT uniquePecaPorPartida UNIQUE (idPartida, idPeca)
);

-- Movimentacao: histórico de ações dentro da partida
CREATE TABLE Movimentacao (
    idMovimentacao SERIAL PRIMARY KEY,
    idPartida INT NOT NULL REFERENCES Partida(idPartida) ON DELETE CASCADE,
    idUsuario INT NOT NULL REFERENCES Usuario(idUsuario),
    dataHoraAcao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ordemAcao INT NOT NULL, -- ordem da jogada
    tipoAcao VARCHAR(20) NOT NULL, -- 'jogada' | 'comprou' | 'passou'
    idPecaJogada INT REFERENCES Peca(idPeca),
    extremidadeMesa VARCHAR(10) -- 'esquerda'/'direita' ou NULL
);

-- =========================================================
-- POPULAÇÃO INICIAL: peças do dominó
-- =========================================================
-- TRUNCATE TABLE Peca;
INSERT INTO Peca (ladoA, ladoB, pontosPeca) VALUES
(0,0,0),(0,1,1),(0,2,2),(0,3,3),(0,4,4),(0,5,5),(0,6,6),
(1,1,2),(1,2,3),(1,3,4),(1,4,5),(1,5,6),(1,6,7),
(2,2,4),(2,3,5),(2,4,6),(2,5,7),(2,6,8),
(3,3,6),(3,4,7),(3,5,8),(3,6,9),
(4,4,8),(4,5,9),(4,6,10),
(5,5,10),(5,6,11),
(6,6,12);

-- =========================================================
-- FUNÇÕES E PROCEDURES (BASE)
-- =========================================================

-- Verifica se um jogador tem alguma peça que encaixa nas extremidades
CREATE OR REPLACE FUNCTION VerificarJogadasPossiveis(
    pIdPartida INT,
    pIdUsuario INT,
    pValorEsquerda INT,
    pValorDireita INT
) RETURNS BOOLEAN
LANGUAGE plpgsql AS $$
DECLARE
    vExiste BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM MaoPartida mp
        JOIN Peca p ON mp.idPeca = p.idPeca
        WHERE mp.idPartida = pIdPartida
          AND mp.idUsuario = pIdUsuario
          AND mp.statusPeca = 'em_mao'
          AND (
                p.ladoA = pValorEsquerda OR p.ladoB = pValorEsquerda
             OR p.ladoA = pValorDireita  OR p.ladoB = pValorDireita
          )
    ) INTO vExiste;
    RETURN vExiste;
END;
$$;


-- Detecta se o jogo está trancado (nenhum jogador com peça válida)
CREATE OR REPLACE FUNCTION DetectarJogoTrancado(
    pIdPartida INT,
    pValorEsquerda INT,
    pValorDireita INT
) RETURNS BOOLEAN
LANGUAGE plpgsql AS $$
DECLARE
    vTrancado BOOLEAN := TRUE;
    vIdUsuario INT;
BEGIN
    FOR vIdUsuario IN
        SELECT DISTINCT idUsuario FROM MaoPartida WHERE idPartida = pIdPartida AND idUsuario IS NOT NULL
    LOOP
        IF VerificarJogadasPossiveis(pIdPartida, vIdUsuario, pValorEsquerda, pValorDireita) THEN
            vTrancado := FALSE;
            EXIT;
        END IF;
    END LOOP;
    RETURN vTrancado;
END;
$$;


-- Procedure: comprar peça do monte (para 2/3 players)
CREATE OR REPLACE PROCEDURE ComprarPecaDoMonte(
    IN pIdPartida INT,
    IN pIdUsuario INT
)
LANGUAGE plpgsql AS $$
DECLARE
    vIdPeca INT;
BEGIN
    SELECT idPeca INTO vIdPeca
    FROM MaoPartida
    WHERE idPartida = pIdPartida
      AND statusPeca = 'no_monte'
    LIMIT 1;

    IF vIdPeca IS NULL THEN
        RAISE NOTICE 'Monte vazio.';
        RETURN;
    END IF;

    UPDATE MaoPartida
    SET idUsuario = pIdUsuario,
        statusPeca = 'em_mao'
    WHERE idPartida = pIdPartida
      AND idPeca = vIdPeca;

    INSERT INTO Movimentacao (idPartida, idUsuario, ordemAcao, tipoAcao, idPecaJogada)
    VALUES (pIdPartida, pIdUsuario, COALESCE((SELECT MAX(ordemAcao) FROM Movimentacao WHERE idPartida = pIdPartida),0)+1, 'comprou', vIdPeca);

    RAISE NOTICE 'Jogador % comprou peça %', pIdUsuario, vIdPeca;
END;
$$;

-- Procedure: validar jogada (apenas valida encaixe e grava movimentacao; NÃO atualiza pontuação da partida)
CREATE OR REPLACE PROCEDURE ValidarJogada(
    IN pIdPartida INT,
    IN pIdUsuario INT,
    IN pIdPeca INT,
    IN pExtremidade VARCHAR(10),
    IN pValorExtremidade INT
)
LANGUAGE plpgsql AS $$
DECLARE
    vLadoA INT;
    vLadoB INT;
    vValida BOOLEAN := FALSE;
BEGIN
    SELECT ladoA, ladoB INTO vLadoA, vLadoB FROM Peca WHERE idPeca = pIdPeca;

    IF vLadoA = pValorExtremidade OR vLadoB = pValorExtremidade THEN
        vValida := TRUE;
    END IF;

    IF vValida THEN
        -- marca peça como jogada (retira da mão)
        UPDATE MaoPartida
        SET statusPeca = 'jogada',
            idUsuario = NULL
        WHERE idPartida = pIdPartida
          AND idPeca = pIdPeca
          AND idUsuario = pIdUsuario;

        INSERT INTO Movimentacao (idPartida, idUsuario, ordemAcao, tipoAcao, idPecaJogada, extremidadeMesa)
        VALUES (pIdPartida, pIdUsuario, COALESCE((SELECT MAX(ordemAcao) FROM Movimentacao WHERE idPartida = pIdPartida),0)+1, 'jogada', pIdPeca, pExtremidade);

        RAISE NOTICE 'Jogada válida: peça % por jogador % na %', pIdPeca, pIdUsuario, pExtremidade;
    ELSE
        RAISE NOTICE 'Jogada inválida: peça % não encaixa em %', pIdPeca, pValorExtremidade;
    END IF;
END;
$$;

-- =========================================================
-- FUNÇÃO E GATILHO PARA CÁLCULO AUTOMÁTICO DE PONTOS
-- =========================================================

-- Função para calcular pontos quando partida termina
CREATE OR REPLACE FUNCTION calcularPontosPartida()
RETURNS TRIGGER AS $$
DECLARE
    totalPontosAdversarios INTEGER;
    idVencedor INTEGER;
    idDuplaVencedora INTEGER;
BEGIN
    -- Só calcula se a partida está sendo finalizada (dataHoraFim preenchido)
    IF NEW.dataHoraFim IS NOT NULL AND OLD.dataHoraFim IS NULL THEN
        -- Se partida terminou por "bater"
        IF NEW.modoTermino = 'bater' THEN
            -- Se é jogo de duplas (4 jogadores)
            IF NEW.idDuplaVencedora IS NOT NULL THEN
                -- Calcula soma dos pontos da dupla adversária
                SELECT COALESCE(SUM(MP.pontosPeca), 0)
                INTO totalPontosAdversarios
                FROM MaoPartida MP
                JOIN PartidaUsuario PU ON MP.idUsuario = PU.idUsuario
                WHERE MP.idPartida = NEW.idPartida
                  AND MP.statusPeca = 'em_mao'
                  AND PU.idDupla != NEW.idDuplaVencedora;
                  
                NEW.pontosDaPartida := totalPontosAdversarios;
                
            -- Se é jogo individual (2 ou 3 jogadores)
            ELSIF NEW.idJogadorVencedor IS NOT NULL THEN
                -- Calcula soma dos pontos dos adversários
                SELECT COALESCE(SUM(MP.pontosPeca), 0)
                INTO totalPontosAdversarios
                FROM MaoPartida MP
                WHERE MP.idPartida = NEW.idPartida
                  AND MP.statusPeca = 'em_mao'
                  AND MP.idUsuario != NEW.idJogadorVencedor;
                  
                NEW.pontosDaPartida := totalPontosAdversarios;
            END IF;
            
        -- Se partida terminou "trancada"
        ELSIF NEW.modoTermino = 'trancado' THEN
            -- Na regra do dominó, quem trancou ganha os pontos do adversário com MENOS pontos
            IF NEW.idDuplaTrancou IS NOT NULL THEN
                -- Encontra a dupla com menos pontos
                WITH PontosDuplas AS (
                    SELECT 
                        PU.idDupla,
                        SUM(MP.pontosPeca) as totalPontos
                    FROM MaoPartida MP
                    JOIN PartidaUsuario PU ON MP.idUsuario = PU.idUsuario
                    WHERE MP.idPartida = NEW.idPartida
                      AND MP.statusPeca = 'em_mao'
                    GROUP BY PU.idDupla
                )
                SELECT MIN(totalPontos)
                INTO totalPontosAdversarios
                FROM PontosDuplas
                WHERE idDupla != NEW.idDuplaTrancou;
                
                NEW.pontosDaPartida := COALESCE(totalPontosAdversarios, 0);
                
            -- Para jogo individual trancado
            ELSIF NEW.idJogadorVencedor IS NOT NULL THEN
                -- Encontra o jogador com menos pontos
                WITH PontosJogadores AS (
                    SELECT 
                        MP.idUsuario,
                        SUM(MP.pontosPeca) as totalPontos
                    FROM MaoPartida MP
                    WHERE MP.idPartida = NEW.idPartida
                      AND MP.statusPeca = 'em_mao'
                    GROUP BY MP.idUsuario
                )
                SELECT MIN(totalPontos)
                INTO totalPontosAdversarios
                FROM PontosJogadores
                WHERE idUsuario != NEW.idJogadorVencedor;
                
                NEW.pontosDaPartida := COALESCE(totalPontosAdversarios, 0);
            END IF;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Gatilho para calcular pontos automaticamente
CREATE TRIGGER trigCalcularPontosPartida
    BEFORE UPDATE ON Partida
    FOR EACH ROW
    EXECUTE FUNCTION calcularPontosPartida();


-- =========================================================
-- VISÃO: RANKING DE PONTUAÇÃO POR USUÁRIO
-- =========================================================

CREATE OR REPLACE VIEW RankingUsuarios AS
WITH PartidasVencidas AS (
    -- Partidas vencidas como jogador individual
    SELECT 
        P.idJogadorVencedor as idUsuario,
        COUNT(*) as partidasVencidas,
        SUM(P.pontosDaPartida) as totalPontos
    FROM Partida P
    WHERE P.idJogadorVencedor IS NOT NULL
    GROUP BY P.idJogadorVencedor
    
    UNION ALL
    
    -- Partidas vencidas como parte de uma dupla
    SELECT 
        PU.idUsuario,
        COUNT(*) as partidasVencidas,
        SUM(P.pontosDaPartida) as totalPontos
    FROM Partida P
    JOIN Dupla D ON P.idDuplaVencedora = D.idDupla
    JOIN PartidaUsuario PU ON D.idDupla = PU.idDupla AND P.idPartida = PU.idPartida
    WHERE P.idDuplaVencedora IS NOT NULL
    GROUP BY PU.idUsuario
),
TotalPartidas AS (
    -- Total de partidas jogadas por usuário
    SELECT 
        PU.idUsuario,
        COUNT(DISTINCT PU.idPartida) as totalPartidasJogadas
    FROM PartidaUsuario PU
    GROUP BY PU.idUsuario
)
SELECT 
    U.idUsuario,
    U.nome,
    COALESCE(TP.totalPartidasJogadas, 0) as totalPartidasJogadas,
    COALESCE(PV.partidasVencidas, 0) as partidasVencidas,
    ROUND(
        CASE 
            WHEN COALESCE(TP.totalPartidasJogadas, 0) = 0 THEN 0 
            ELSE (COALESCE(PV.partidasVencidas, 0) * 100.0 / TP.totalPartidasJogadas) 
        END, 2
    ) as percentualVitorias,
    COALESCE(PV.totalPontos, 0) as totalPontosGanhos,
    ROUND(
        CASE 
            WHEN COALESCE(TP.totalPartidasJogadas, 0) = 0 THEN 0 
            ELSE (COALESCE(PV.totalPontos, 0) * 1.0 / TP.totalPartidasJogadas) 
        END, 2
    ) as mediaPontosPorPartida
FROM Usuario U
LEFT JOIN TotalPartidas TP ON U.idUsuario = TP.idUsuario
LEFT JOIN (
    SELECT 
        idUsuario,
        SUM(partidasVencidas) as partidasVencidas,
        SUM(totalPontos) as totalPontos
    FROM PartidasVencidas
    GROUP BY idUsuario
) PV ON U.idUsuario = PV.idUsuario
ORDER BY partidasVencidas DESC, totalPontosGanhos DESC;

-- =========================================================
-- VISÃO: LISTAGEM DE PARTIDAS E VENCEDORES
-- =========================================================

CREATE OR REPLACE VIEW PartidasDetalhadas AS
SELECT 
    P.idPartida,
    P.dataHoraInicio,
    P.dataHoraFim,
    P.modoTermino,
    P.pontosDaPartida,
    
    -- Informações do vencedor individual
    CASE 
        WHEN P.idJogadorVencedor IS NOT NULL THEN 'Jogador Individual'
        WHEN P.idDuplaVencedora IS NOT NULL THEN 'Dupla'
        ELSE 'Sem vencedor'
    END as tipoVitoria,
    
    -- Detalhes do vencedor individual
    UV.nome as nomeVencedorIndividual,
    
    -- Detalhes da dupla vencedora
    D.nomeDupla as nomeDuplaVencedora,
    
    -- Detalhes do trancamento
    DT.nomeDupla as nomeDuplaTrancou,
    
    -- Jogadores participantes
    (
        SELECT STRING_AGG(U.nome, ', ' ORDER BY PU.posicaoMesa)
        FROM PartidaUsuario PU
        JOIN Usuario U ON PU.idUsuario = U.idUsuario
        WHERE PU.idPartida = P.idPartida
    ) as jogadoresParticipantes,
    
    -- Duplas participantes (se houver)
    (
        SELECT STRING_AGG(DISTINCT D2.nomeDupla, ', ')
        FROM PartidaUsuario PU2
        JOIN Dupla D2 ON PU2.idDupla = D2.idDupla
        WHERE PU2.idPartida = P.idPartida
    ) as duplasParticipantes,
    
    -- Total de movimentações na partida
    (
        SELECT COUNT(*) 
        FROM Movimentacao M 
        WHERE M.idPartida = P.idPartida
    ) as totalMovimentacoes,
    
    -- Duração da partida em minutos
    CASE 
        WHEN P.dataHoraFim IS NOT NULL THEN
            EXTRACT(EPOCH FROM (P.dataHoraFim - P.dataHoraInicio)) / 60
        ELSE NULL
    END as duracaoMinutos

FROM Partida P
LEFT JOIN Usuario UV ON P.idJogadorVencedor = UV.idUsuario
LEFT JOIN Dupla D ON P.idDuplaVencedora = D.idDupla
LEFT JOIN Dupla DT ON P.idDuplaTrancou = DT.idDupla
ORDER BY P.dataHoraInicio DESC;
