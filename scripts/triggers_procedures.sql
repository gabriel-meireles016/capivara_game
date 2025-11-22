--------- TRIGGERS ---------

CREATE OR REPLACE FUNCTION calcular_pontos_partida()
RETURNS TRIGGER AS $$
DECLARE
    v_id_sessao_jogo INTEGER;
    v_dupla_vencedora INTEGER;
    v_pontos_partida INTEGER;
    v_pontos_dupla1 INTEGER;
    v_pontos_dupla2 INTEGER;
    v_dupla_jogador1 INTEGER;
    v_dupla_jogador2 INTEGER;
BEGIN
    IF NEW.ID_DuplaVencedora IS NOT NULL AND OLD.ID_DuplaVencedora IS NULL THEN
        SELECT ID_SessaoJogo INTO v_id_sessao_jogo
        FROM Partida WHERE ID_Partida = NEW.ID_Partida;
        
        SELECT COALESCE(SUM(p.PontosPeca), 0) INTO v_pontos_partida
        FROM MaoPartida mp
        JOIN Peca p ON mp.ID_Peca = p.ID_Peca
        WHERE mp.ID_Partida = NEW.ID_Partida
        AND mp.StatusPeca = 'na_mao'
        AND mp.ID_Usuario IN (
            SELECT su.ID_Usuario 
            FROM Sessao_Usuario su 
            WHERE su.ID_SessaoJogo = v_id_sessao_jogo 
            AND su.ID_Dupla != NEW.ID_DuplaVencedora
        );
        
        UPDATE Dupla 
        SET PontuacaoTotalSessao = PontuacaoTotalSessao + v_pontos_partida
        WHERE ID_Dupla = NEW.ID_DuplaVencedora;
        
        UPDATE Partida 
        SET PontosDaPartida = v_pontos_partida
        WHERE ID_Partida = NEW.ID_Partida;
        
        SELECT 
            MAX(CASE WHEN d.ID_Dupla = dupla1 THEN d.PontuacaoTotalSessao ELSE 0 END),
            MAX(CASE WHEN d.ID_Dupla = dupla2 THEN d.PontuacaoTotalSessao ELSE 0 END)
        INTO v_pontos_dupla1, v_pontos_dupla2
        FROM Dupla d
        CROSS JOIN (
            SELECT 
                MIN(ID_Dupla) as dupla1,
                MAX(ID_Dupla) as dupla2
            FROM Dupla 
            WHERE ID_SessaoJogo = v_id_sessao_jogo
        ) duplas
        WHERE d.ID_SessaoJogo = v_id_sessao_jogo;
        
        DECLARE
            v_pontuacao_alvo INTEGER;
        BEGIN
            SELECT PontuacaoAlvo INTO v_pontuacao_alvo
            FROM TipoJogo tj
            JOIN SessaoJogo sj ON tj.ID_TipoJogo = sj.ID_TipoJogo
            WHERE sj.ID_SessaoJogo = v_id_sessao_jogo;
            
            IF v_pontos_dupla1 >= v_pontuacao_alvo OR v_pontos_dupla2 >= v_pontuacao_alvo THEN
                UPDATE SessaoJogo 
                SET 
                    DataHoraFim = CURRENT_TIMESTAMP,
                    ID_DuplaVencedora = CASE 
                        WHEN v_pontos_dupla1 >= v_pontuacao_alvo THEN 
                            (SELECT ID_Dupla FROM Dupla WHERE ID_SessaoJogo = v_id_sessao_jogo ORDER BY ID_Dupla LIMIT 1)
                        ELSE 
                            (SELECT ID_Dupla FROM Dupla WHERE ID_SessaoJogo = v_id_sessao_jogo ORDER BY ID_Dupla DESC LIMIT 1)
                    END
                WHERE ID_SessaoJogo = v_id_sessao_jogo;
            END IF;
        END;
        
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_calcular_pontos ON Partida;

CREATE TRIGGER tr_calcular_pontos
    AFTER UPDATE ON Partida
    FOR EACH ROW
    EXECUTE FUNCTION calcular_pontos_partida();

--------- VIEW ---------

CREATE OR REPLACE VIEW RankingUsuarios AS
SELECT 
    u.ID_Usuario,
    u.Nome,
    u.Email,
    COUNT(DISTINCT p.ID_Partida) AS PartidasVencidas,
    COUNT(DISTINCT CASE WHEN sj.ID_DuplaVencedora = su.ID_Dupla THEN sj.ID_SessaoJogo END) AS JogosVencidos,
    COALESCE(SUM(d.PontuacaoTotalSessao), 0) AS PontuacaoTotal,
    MAX(sj.DataHoraInicio) AS UltimaParticipacao
FROM 
    Usuario u
LEFT JOIN Sessao_Usuario su ON u.ID_Usuario = su.ID_Usuario
LEFT JOIN SessaoJogo sj ON su.ID_SessaoJogo = sj.ID_SessaoJogo
LEFT JOIN Dupla d ON su.ID_Dupla = d.ID_Dupla
LEFT JOIN Partida p ON p.ID_SessaoJogo = sj.ID_SessaoJogo AND p.ID_DuplaVencedora = su.ID_Dupla
GROUP BY 
    u.ID_Usuario, u.Nome, u.Email
ORDER BY 
    PontuacaoTotal DESC, PartidasVencidas DESC, JogosVencidos DESC;

--------- VIEW ---------

CREATE OR REPLACE VIEW DetalhesSessoes AS
SELECT 
    sj.ID_SessaoJogo,
    tj.NomeJogo,
    sj.DataHoraInicio,
    sj.DataHoraFim,
    d_venc.NomeDupla AS DuplaVencedoraSessao,
    COUNT(p.ID_Partida) AS TotalPartidas,
    COUNT(p.ID_DuplaVencedora) AS PartidasFinalizadas,
    MAX(CASE WHEN d1.ID_Dupla IS NOT NULL THEN d1.PontuacaoTotalSessao END) AS PontuacaoDupla1,
    MAX(CASE WHEN d2.ID_Dupla IS NOT NULL THEN d2.PontuacaoTotalSessao END) AS PontuacaoDupla2,
    MAX(CASE WHEN d1.ID_Dupla IS NOT NULL THEN d1.NomeDupla END) AS NomeDupla1,
    MAX(CASE WHEN d2.ID_Dupla IS NOT NULL THEN d2.NomeDupla END) AS NomeDupla2
FROM 
    SessaoJogo sj
INNER JOIN TipoJogo tj ON sj.ID_TipoJogo = tj.ID_TipoJogo
LEFT JOIN Dupla d_venc ON sj.ID_DuplaVencedora = d_venc.ID_Dupla
LEFT JOIN Partida p ON sj.ID_SessaoJogo = p.ID_SessaoJogo
LEFT JOIN (
    SELECT ID_Dupla, NomeDupla, PontuacaoTotalSessao, ID_SessaoJogo
    FROM Dupla
    WHERE ID_Dupla IN (
        SELECT MIN(ID_Dupla) FROM Dupla GROUP BY ID_SessaoJogo
    )
) d1 ON sj.ID_SessaoJogo = d1.ID_SessaoJogo
LEFT JOIN (
    SELECT ID_Dupla, NomeDupla, PontuacaoTotalSessao, ID_SessaoJogo
    FROM Dupla
    WHERE ID_Dupla IN (
        SELECT MAX(ID_Dupla) FROM Dupla GROUP BY ID_SessaoJogo
    )
) d2 ON sj.ID_SessaoJogo = d2.ID_SessaoJogo
GROUP BY 
    sj.ID_SessaoJogo,
    tj.NomeJogo,
    sj.DataHoraInicio,
    sj.DataHoraFim,
    d_venc.NomeDupla
ORDER BY 
    sj.DataHoraInicio DESC;