CREATE TABLE Usuario (
    idUsuario    SERIAL PRIMARY KEY,
    nome          VARCHAR(255) NOT NULL,
    dataCadastro  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Peca (
    idPeca    SERIAL PRIMARY KEY,
    ladoA      INT NOT NULL CHECK (ladoA BETWEEN 0 AND 6),
    ladoB      INT NOT NULL CHECK (ladoB BETWEEN 0 AND 6),
    pontosPeca INT NOT NULL 
);

CREATE TABLE Partida (
    idPartida SERIAL PRIMARY KEY,
    idJogadorIniciou INT,                    
    idJogadorVencedor INT,                  
    idDuplaVencedora INT, 
    idDuplaTrancou INT,   
    pontosDaPartida INT NOT NULL DEFAULT 0,    
    modoTermino VARCHAR(20),                  
    valorExtEsquerda INT,                      
    valorExtDireita INT,
    dataHoraInicio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dataHoraFim TIMESTAMP
);


CREATE TABLE Dupla (
    idDupla INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    idPartida INT NOT NULL REFERENCES Partida(idPartida) ON DELETE CASCADE,
    nomeDupla VARCHAR(100) NOT NULL,
    pontuacaoTotal INT NOT NULL DEFAULT 0
);

ALTER TABLE Partida ADD FOREIGN KEY (idDuplaVencedora) REFERENCES Dupla(idDupla);
ALTER TABLE Partida ADD FOREIGN KEY (idDuplaTrancou) REFERENCES Dupla(idDupla);

CREATE TABLE PartidaUsuario (
    idPartida INT NOT NULL REFERENCES Partida(idPartida) ON DELETE CASCADE,
    idUsuario    INT NOT NULL REFERENCES Usuario(idUsuario) ON DELETE CASCADE,
    idDupla      INT REFERENCES Dupla(idDupla),
    posicaoMesa   INT NOT NULL,
    PRIMARY KEY (idPartida, idUsuario)
);

CREATE TABLE MaoPartida (
    idMaoPartida SERIAL PRIMARY KEY,
    idPartida INT NOT NULL REFERENCES Partida(idPartida) ON DELETE CASCADE,
    idPeca INT NOT NULL REFERENCES Peca(idPeca),
    idUsuario INT, 
    statusPeca VARCHAR(20) NOT NULL CHECK (statusPeca IN ('no_monte','em_mao','jogada')),
    CONSTRAINT uniquePecaPorPartida UNIQUE (idPartida, idPeca)
);

CREATE TABLE Movimentacao (
    idMovimentacao SERIAL PRIMARY KEY,
    idPartida INT NOT NULL REFERENCES Partida(idPartida) ON DELETE CASCADE,
    idUsuario INT NOT NULL REFERENCES Usuario(idUsuario),
    dataHoraAcao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ordemAcao INT NOT NULL, 
    tipoAcao VARCHAR(20) NOT NULL, 
    idPecaJogada INT REFERENCES Peca(idPeca),
    extremidadeMesa VARCHAR(10) 
);


INSERT INTO Peca (ladoA, ladoB, pontosPeca) VALUES
(0,0,0),(0,1,1),(0,2,2),(0,3,3),(0,4,4),(0,5,5),(0,6,6),
(1,1,2),(1,2,3),(1,3,4),(1,4,5),(1,5,6),(1,6,7),
(2,2,4),(2,3,5),(2,4,6),(2,5,7),(2,6,8),
(3,3,6),(3,4,7),(3,5,8),(3,6,9),
(4,4,8),(4,5,9),(4,6,10),
(5,5,10),(5,6,11),
(6,6,12);


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

CREATE OR REPLACE FUNCTION calcularPontosPartida()
RETURNS TRIGGER AS $$
DECLARE
    totalPontosAdversarios INTEGER;
    idVencedor INTEGER;
    idDuplaVencedora INTEGER;
BEGIN
    IF NEW.dataHoraFim IS NOT NULL AND OLD.dataHoraFim IS NULL THEN
        IF NEW.modoTermino = 'bater' THEN
            IF NEW.idDuplaVencedora IS NOT NULL THEN
                SELECT COALESCE(SUM(MP.pontosPeca), 0)
                INTO totalPontosAdversarios
                FROM MaoPartida MP
                JOIN PartidaUsuario PU ON MP.idUsuario = PU.idUsuario
                WHERE MP.idPartida = NEW.idPartida
                  AND MP.statusPeca = 'em_mao'
                  AND PU.idDupla != NEW.idDuplaVencedora;
                  
                NEW.pontosDaPartida := totalPontosAdversarios;
                
            ELSIF NEW.idJogadorVencedor IS NOT NULL THEN
                SELECT COALESCE(SUM(MP.pontosPeca), 0)
                INTO totalPontosAdversarios
                FROM MaoPartida MP
                WHERE MP.idPartida = NEW.idPartida
                  AND MP.statusPeca = 'em_mao'
                  AND MP.idUsuario != NEW.idJogadorVencedor;
                  
                NEW.pontosDaPartida := totalPontosAdversarios;
            END IF;
            
        ELSIF NEW.modoTermino = 'trancado' THEN
            IF NEW.idDuplaTrancou IS NOT NULL THEN
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
                
            ELSIF NEW.idJogadorVencedor IS NOT NULL THEN
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

CREATE TRIGGER trigCalcularPontosPartida
    BEFORE UPDATE ON Partida
    FOR EACH ROW
    EXECUTE FUNCTION calcularPontosPartida();


CREATE OR REPLACE VIEW RankingUsuarios AS
WITH PartidasVencidas AS (
    SELECT 
        P.idJogadorVencedor as idUsuario,
        COUNT(*) as partidasVencidas,
        SUM(P.pontosDaPartida) as totalPontos
    FROM Partida P
    WHERE P.idJogadorVencedor IS NOT NULL
    GROUP BY P.idJogadorVencedor
    
    UNION ALL
    
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

CREATE OR REPLACE VIEW PartidasDetalhadas AS
SELECT 
    P.idPartida,
    P.dataHoraInicio,
    P.dataHoraFim,
    P.modoTermino,
    P.pontosDaPartida,
    
    CASE 
        WHEN P.idJogadorVencedor IS NOT NULL THEN 'Jogador Individual'
        WHEN P.idDuplaVencedora IS NOT NULL THEN 'Dupla'
        ELSE 'Sem vencedor'
    END as tipoVitoria,
    
    UV.nome as nomeVencedorIndividual,
    
    D.nomeDupla as nomeDuplaVencedora,
    
    DT.nomeDupla as nomeDuplaTrancou,
    
    (
        SELECT STRING_AGG(U.nome, ', ' ORDER BY PU.posicaoMesa)
        FROM PartidaUsuario PU
        JOIN Usuario U ON PU.idUsuario = U.idUsuario
        WHERE PU.idPartida = P.idPartida
    ) as jogadoresParticipantes,
    
    (
        SELECT STRING_AGG(DISTINCT D2.nomeDupla, ', ')
        FROM PartidaUsuario PU2
        JOIN Dupla D2 ON PU2.idDupla = D2.idDupla
        WHERE PU2.idPartida = P.idPartida
    ) as duplasParticipantes,
    
    (
        SELECT COUNT(*) 
        FROM Movimentacao M 
        WHERE M.idPartida = P.idPartida
    ) as totalMovimentacoes,
    
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
