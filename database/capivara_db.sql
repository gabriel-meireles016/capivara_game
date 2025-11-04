CREATE TABLE TipoJogo (
    ID_TipoJogo SERIAL PRIMARY KEY,
    NomeJogo VARCHAR(100) NOT NULL,
    PontuacaoAlvo INT NOT NULL DEFAULT 50
);

CREATE TABLE Usuario (
    ID_Usuario SERIAL PRIMARY KEY,
    Nome VARCHAR(255) NOT NULL,
    Email VARCHAR(100) NOT NULL UNIQUE,
    Senha VARCHAR(255) NOT NULL,
    DataCadastro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Peca (
    ID_Peca SERIAL PRIMARY KEY,
    LadoA INT NOT NULL,
    LadoB INT NOT NULL,
    PontosPeca INT NOT NULL
);

CREATE TABLE SessaoJogo (
    ID_SessaoJogo SERIAL PRIMARY KEY,
    ID_TipoJogo INT NOT NULL,
    DataHoraInicio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    DataHoraFim TIMESTAMP,
    ID_DuplaVencedora INT,
    
    FOREIGN KEY (ID_TipoJogo) REFERENCES TipoJogo(ID_TipoJogo)
);

CREATE TABLE Dupla (
    ID_Dupla SERIAL PRIMARY KEY,
    ID_SessaoJogo INT NOT NULL,
    NomeDupla VARCHAR(100) NOT NULL,
    PontuacaoTotalSessao INT NOT NULL DEFAULT 0,
    
    FOREIGN KEY (ID_SessaoJogo) REFERENCES SessaoJogo(ID_SessaoJogo)
);

CREATE TABLE Sessao_Usuario (
    ID_SessaoJogo INT NOT NULL,
    ID_Usuario INT NOT NULL,
    ID_Dupla INT,
    PosicaoMesa INT NOT NULL,
    
    PRIMARY KEY (ID_SessaoJogo, ID_Usuario),
    FOREIGN KEY (ID_SessaoJogo) REFERENCES SessaoJogo(ID_SessaoJogo),
    FOREIGN KEY (ID_Usuario) REFERENCES Usuario(ID_Usuario),
    FOREIGN KEY (ID_Dupla) REFERENCES Dupla(ID_Dupla)
);

CREATE TABLE Partida (
    ID_Partida SERIAL PRIMARY KEY,
    ID_SessaoJogo INT NOT NULL,
    ID_JogadorIniciou INT NOT NULL,
    ID_DuplaVencedora INT,
    PontosDaPartida INT NOT NULL DEFAULT 0,
    ModoTermino VARCHAR(50),
    
    FOREIGN KEY (ID_SessaoJogo) REFERENCES SessaoJogo(ID_SessaoJogo),
    FOREIGN KEY (ID_JogadorIniciou) REFERENCES Usuario(ID_Usuario),
    FOREIGN KEY (ID_DuplaVencedora) REFERENCES Dupla(ID_Dupla)
);

CREATE TABLE MaoPartida (
    ID_Partida INT NOT NULL,
    ID_Peca INT NOT NULL,
    ID_Usuario INT,
    StatusPeca VARCHAR(50) NOT NULL,
    
    PRIMARY KEY (ID_Partida, ID_Peca),
    FOREIGN KEY (ID_Partida) REFERENCES Partida(ID_Partida),
    FOREIGN KEY (ID_Peca) REFERENCES Peca(ID_Peca),
    FOREIGN KEY (ID_Usuario) REFERENCES Usuario(ID_Usuario)
);

CREATE TABLE Movimentacao (
    ID_Movimentacao SERIAL PRIMARY KEY,
    ID_Partida INT NOT NULL,
    ID_Usuario INT NOT NULL,
    DataHoraAcao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    OrdemAcao INT NOT NULL,
    TipoAcao VARCHAR(50) NOT NULL,
    ID_PecaJogada INT,
    ExtremidadeMesa VARCHAR(10),
    
    FOREIGN KEY (ID_Partida) REFERENCES Partida(ID_Partida),
    FOREIGN KEY (ID_Usuario) REFERENCES Usuario(ID_Usuario),
    FOREIGN KEY (ID_PecaJogada) REFERENCES Peca(ID_Peca)
);

ALTER TABLE SessaoJogo
ADD CONSTRAINT fk_dupla_vencedora
FOREIGN KEY (ID_DuplaVencedora) REFERENCES Dupla(ID_Dupla);

INSERT INTO Peca (LadoA, LadoB, PontosPeca) VALUES
(0,0,0), (0,1,1), (0,2,2), (0,3,3), (0,4,4), (0,5,5), (0,6,6),
(1,1,2), (1,2,3), (1,3,4), (1,4,5), (1,5,6), (1,6,7),
(2,2,4), (2,3,5), (2,4,6), (2,5,7), (2,6,8),
(3,3,6), (3,4,7), (3,5,8), (3,6,9),
(4,4,8), 
(4,5,9), 
(4,6,10),
(5,5,10), 
(5,6,11),
(6,6,12);

COMMIT;