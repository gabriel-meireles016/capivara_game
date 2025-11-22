from database import session, tables

#Pegando a tabela usuario e guardandos na variável Usuario
Usuario = tables.usuario

def mostrar_usuarios():
    usuarios = session.query(Usuario).all()
    for u in usuarios:
        print(f"ID: {u.id_usuario}, Nome: {u.nome}")
