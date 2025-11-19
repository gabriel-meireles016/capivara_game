from database import session, tables

#Pegando a tabela usuario e guardandos na variável Usuario
Usuario = tables.usuario

# SELECT * FROM usuario
usuarios = session.query(Usuario).all()

for u in usuarios:
    print(u.id_usuario, u.nome)
