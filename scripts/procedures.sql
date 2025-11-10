#Function e procedures (sempre executar nessa ordem se n quebra)

CREATE OR REPLACE PROCEDURE ComprarPecaDoMonte(
    IN p_id_partida INT,
    IN p_id_usuario INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_peca INT;
BEGIN

    SELECT ID_Peca
    INTO v_id_peca
    FROM MaoPartida
    WHERE ID_Partida = p_id_partida
      AND StatusPeca = 'no_monte'
    LIMIT 1;


    IF v_id_peca IS NULL THEN
        RAISE NOTICE 'Não existem mais peças no monte.';
        RETURN;
    END IF;


    UPDATE MaoPartida
    SET ID_Usuario = p_id_usuario,
        StatusPeca = 'em_mao'
    WHERE ID_Partida = p_id_partida
      AND ID_Peca = v_id_peca;

    RAISE NOTICE 'O Jogador % comprou a peça %', p_id_usuario, v_id_peca;
END;
$$;


CREATE OR REPLACE PROCEDURE ValidarJogada(
    IN p_id_partida INT,
    IN p_id_usuario INT,
    IN p_id_peca INT,
    IN p_extremidade VARCHAR(10),
    IN p_valor_extremidade INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_ladoA INT;
    v_ladoB INT;
    v_valida BOOLEAN := FALSE;
BEGIN

    SELECT LadoA, LadoB
    INTO v_ladoA, v_ladoB
    FROM Peca
    WHERE ID_Peca = p_id_peca;


    IF v_ladoA = p_valor_extremidade OR v_ladoB = p_valor_extremidade THEN
        v_valida := TRUE;
    END IF;

  
    IF v_valida THEN
        UPDATE MaoPartida
        SET StatusPeca = 'jogada'
        WHERE ID_Partida = p_id_partida
          AND ID_Peca = p_id_peca
          AND ID_Usuario = p_id_usuario;

        INSERT INTO Movimentacao (
            ID_Partida,
            ID_Usuario,
            TipoAcao,
            ID_PecaJogada,
            ExtremidadeMesa
        )
        VALUES (
            p_id_partida,
            p_id_usuario,
            'jogada',
            p_id_peca,
            p_extremidade
        );

        RAISE NOTICE 'Jogada válida: peça % jogada por jogador % na %',
            p_id_peca, p_id_usuario, p_extremidade;

    ELSE
        RAISE NOTICE 'Jogada inválida: peça % não encaixa no valor %',
            p_id_peca, p_valor_extremidade;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION VerificarJogadasPossiveis(
    p_id_partida INT,
    p_id_usuario INT,
    p_valor_esquerda INT,
    p_valor_direita INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_existe BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM MaoPartida mp
        JOIN Peca p ON mp.ID_Peca = p.ID_Peca
        WHERE mp.ID_Partida = p_id_partida
          AND mp.ID_Usuario = p_id_usuario
          AND mp.StatusPeca = 'em_mao'
          AND (p.LadoA = p_valor_esquerda OR p.LadoB = p_valor_esquerda
            OR p.LadoA = p_valor_direita OR p.LadoB = p_valor_direita)
    )
    INTO v_existe;

    RETURN v_existe;
END;
$$;


CREATE OR REPLACE FUNCTION DetectarJogoTrancado(
    p_id_partida INT,
    p_valor_esquerda INT,
    p_valor_direita INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_trancado BOOLEAN := TRUE;
    v_id_usuario INT;
BEGIN
    FOR v_id_usuario IN
        SELECT DISTINCT ID_Usuario
        FROM MaoPartida
        WHERE ID_Partida = p_id_partida
          AND ID_Usuario IS NOT NULL
    LOOP
        IF VerificarJogadasPossiveis(p_id_partida, v_id_usuario, p_valor_esquerda, p_valor_direita) THEN
            v_trancado := FALSE;
            EXIT; 
        END IF;
    END LOOP;

    RETURN v_trancado;
END;
$$;
