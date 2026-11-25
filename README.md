# ACHEI · Marketplace de classificados

Site estático (`index.html`) + Supabase (`schema.sql`). Sem build, sem servidor próprio.

## 1. Supabase
1. Crie um projeto em supabase.com.
2. **SQL Editor**: cole e execute `schema.sql` (tabelas, RLS, triggers anti-spam, bucket de imagens, categorias iniciais, realtime).
3. **Project Settings → API**: copie `Project URL` e `anon public key`.
4. Em `index.html`, troque `SUPABASE_URL` e `SUPABASE_KEY` no topo do script. A anon key é pública por design; a segurança vem das políticas RLS.
5. **Authentication → Providers → Google**: ative e informe Client ID/Secret do Google Cloud Console. Em Redirect URLs adicione o domínio da Vercel.
6. **Authentication → URL Configuration**: defina Site URL como o domínio final.
7. Para criar o administrador: cadastre-se no site e rode no SQL Editor  
   `update profiles set is_admin = true where id = (select id from auth.users where email = 'seu@email.com');`

## 2. Vercel
1. Suba a pasta num repositório GitHub.
2. Na Vercel: **Add New → Project**, importe o repositório. Framework: *Other*, sem build command.
3. Deploy. Depois adicione o domínio da Vercel nas Redirect URLs do Supabase (passo 5/6).

## Segurança implementada
- RLS em todas as tabelas: só o dono edita/exclui seus anúncios; só admin modera os de terceiros.
- Triggers impedem usuário comum de se tornar admin, destacar anúncio ou reativar anúncio removido.
- Limite de 5 anúncios por hora por usuário (anti-spam) e validações por `CHECK` no banco.
- Upload só na pasta do próprio usuário; e-mail nunca é exposto publicamente.
