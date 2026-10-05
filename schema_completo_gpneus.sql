-- ============================================================================
-- GPneus — SQL COMPLETO DO BANCO DE DADOS
-- Consolidado a partir do dump original (estrutura_banco.sql) + todas as
-- migrações feitas durante o desenvolvimento (histórico de KM, segurança/
-- logs, alertas). Rode este arquivo inteiro, do início ao fim, num banco
-- Postgres novo chamado "GPneus" pra ter tudo de uma vez.
--
-- Este arquivo é só ESTRUTURA (schema) — não inclui os dados que você já
-- tiver em produção. Se está subindo um banco do zero, rode como está.
-- Se já tem dados e só quer adicionar o que falta, cada bloco usa
-- IF NOT EXISTS / ON CONFLICT, então é seguro rodar de novo sem duplicar.
-- ============================================================================

-- Extensão necessária para gen_random_uuid() (tabela usuarios_sso) e para
-- crypt()/gen_salt() (hash de senha usado no login e no usuário admin abaixo).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 1) SCHEMA ORIGINAL (caminhoes, pneus, movimentacoes, vistorias, usuarios,
--    usuarios_sso, sessions, login_attempts)
-- ============================================================================

-- ---- caminhoes ----
CREATE TABLE IF NOT EXISTS public.caminhoes (
    id               integer NOT NULL,
    frota            character varying(50) NOT NULL,
    placa            character varying(20),
    modelo           character varying(100),
    tipo             character varying(50) DEFAULT 'TOCO'::character varying,
    eixos_traseiros  integer DEFAULT 1,
    filial           character varying(100),
    cnpj             character varying(30),
    criado_em        timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

CREATE SEQUENCE IF NOT EXISTS public.caminhoes_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.caminhoes_id_seq OWNED BY public.caminhoes.id;
ALTER TABLE ONLY public.caminhoes ALTER COLUMN id SET DEFAULT nextval('public.caminhoes_id_seq'::regclass);

ALTER TABLE ONLY public.caminhoes DROP CONSTRAINT IF EXISTS caminhoes_frota_key;
ALTER TABLE ONLY public.caminhoes ADD CONSTRAINT caminhoes_frota_key UNIQUE (frota);
ALTER TABLE ONLY public.caminhoes DROP CONSTRAINT IF EXISTS caminhoes_pkey;
ALTER TABLE ONLY public.caminhoes ADD CONSTRAINT caminhoes_pkey PRIMARY KEY (id);

-- ---- login_attempts (controle de força bruta no login) ----
CREATE TABLE IF NOT EXISTS public.login_attempts (
    id         integer NOT NULL,
    usuario    character varying(100) NOT NULL,
    sucesso    boolean NOT NULL,
    criado_em  timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

CREATE SEQUENCE IF NOT EXISTS public.login_attempts_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.login_attempts_id_seq OWNED BY public.login_attempts.id;
ALTER TABLE ONLY public.login_attempts ALTER COLUMN id SET DEFAULT nextval('public.login_attempts_id_seq'::regclass);

ALTER TABLE ONLY public.login_attempts DROP CONSTRAINT IF EXISTS login_attempts_pkey;
ALTER TABLE ONLY public.login_attempts ADD CONSTRAINT login_attempts_pkey PRIMARY KEY (id);

CREATE INDEX IF NOT EXISTS idx_login_attempts_usuario ON public.login_attempts USING btree (usuario, criado_em);

-- ---- usuarios ----
CREATE TABLE IF NOT EXISTS public.usuarios (
    id          integer NOT NULL,
    nome        character varying(100) NOT NULL,
    senha       character varying(255) NOT NULL,
    perfil      character varying(50) DEFAULT 'operador'::character varying,
    criado_em   timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    permissoes  jsonb DEFAULT '{}'::jsonb
);

CREATE SEQUENCE IF NOT EXISTS public.usuarios_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.usuarios_id_seq OWNED BY public.usuarios.id;
ALTER TABLE ONLY public.usuarios ALTER COLUMN id SET DEFAULT nextval('public.usuarios_id_seq'::regclass);

ALTER TABLE ONLY public.usuarios DROP CONSTRAINT IF EXISTS usuarios_nome_key;
ALTER TABLE ONLY public.usuarios ADD CONSTRAINT usuarios_nome_key UNIQUE (nome);
ALTER TABLE ONLY public.usuarios DROP CONSTRAINT IF EXISTS usuarios_pkey;
ALTER TABLE ONLY public.usuarios ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);

-- ---- usuarios_sso ----
CREATE TABLE IF NOT EXISTS public.usuarios_sso (
    id          uuid DEFAULT gen_random_uuid() NOT NULL,
    nome        character varying(100) NOT NULL,
    email       character varying(150) NOT NULL,
    senha_hash  text NOT NULL,
    ativo       boolean DEFAULT true NOT NULL,
    criado_em   timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE ONLY public.usuarios_sso DROP CONSTRAINT IF EXISTS usuarios_sso_email_key;
ALTER TABLE ONLY public.usuarios_sso ADD CONSTRAINT usuarios_sso_email_key UNIQUE (email);
ALTER TABLE ONLY public.usuarios_sso DROP CONSTRAINT IF EXISTS usuarios_sso_pkey;
ALTER TABLE ONLY public.usuarios_sso ADD CONSTRAINT usuarios_sso_pkey PRIMARY KEY (id);

CREATE INDEX IF NOT EXISTS idx_usuarios_sso_email ON public.usuarios_sso USING btree (email);

-- ---- sessions ----
CREATE TABLE IF NOT EXISTS public.sessions (
    id             integer NOT NULL,
    token          character varying(100) NOT NULL,
    usuario_id     integer,
    usuario_nome   character varying(100) NOT NULL,
    perfil         character varying(50) NOT NULL,
    criado_em      timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expira_em      timestamp without time zone NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.sessions_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;
ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);

ALTER TABLE ONLY public.sessions DROP CONSTRAINT IF EXISTS sessions_pkey;
ALTER TABLE ONLY public.sessions ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.sessions DROP CONSTRAINT IF EXISTS sessions_token_key;
ALTER TABLE ONLY public.sessions ADD CONSTRAINT sessions_token_key UNIQUE (token);

CREATE INDEX IF NOT EXISTS idx_sessions_token ON public.sessions USING btree (token);

ALTER TABLE ONLY public.sessions DROP CONSTRAINT IF EXISTS sessions_usuario_id_fkey;
ALTER TABLE ONLY public.sessions ADD CONSTRAINT sessions_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;

-- ---- pneus ----
CREATE TABLE IF NOT EXISTS public.pneus (
    id                     character varying(100) NOT NULL,
    fogo                   character varying(50) NOT NULL,
    dot                    character varying(20),
    nf                     character varying(50),
    filial                 character varying(100),
    fornecedor             character varying(100),
    marca                  character varying(100),
    modelo                 character varying(100),
    medida                 character varying(50),
    situacao               character varying(50),
    status_atual           character varying(50) DEFAULT 'ESTOQUE'::character varying,
    recape_atual           character varying(50) DEFAULT 'NOVO'::character varying,
    mm_inicial             numeric(5,2) DEFAULT 0,
    mm_atual               numeric(5,2) DEFAULT 0,
    valor_compra           numeric(10,2) DEFAULT 0,
    valor_recapes          numeric(10,2) DEFAULT 0,
    valor_consertos        numeric(10,2) DEFAULT 0,
    caminhao_atual         character varying(50),
    posicao_atual          character varying(50),
    data_cadastro          date,
    operador_cadastro      character varying(100),
    operador_alteracao     character varying(100),
    anomalias              jsonb DEFAULT '[]'::jsonb,
    descarte_data          date,
    descarte_fornecedor    character varying(100),
    descarte_motivo        character varying(255),
    criado_em              timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE ONLY public.pneus DROP CONSTRAINT IF EXISTS pneus_fogo_key;
ALTER TABLE ONLY public.pneus ADD CONSTRAINT pneus_fogo_key UNIQUE (fogo);
ALTER TABLE ONLY public.pneus DROP CONSTRAINT IF EXISTS pneus_pkey;
ALTER TABLE ONLY public.pneus ADD CONSTRAINT pneus_pkey PRIMARY KEY (id);

CREATE INDEX IF NOT EXISTS idx_pneus_caminhao ON public.pneus USING btree (caminhao_atual);
CREATE INDEX IF NOT EXISTS idx_pneus_fogo     ON public.pneus USING btree (fogo);
CREATE INDEX IF NOT EXISTS idx_pneus_status   ON public.pneus USING btree (status_atual);

-- ---- movimentacoes ----
CREATE TABLE IF NOT EXISTS public.movimentacoes (
    id_mov               character varying(100) NOT NULL,
    fogo                 character varying(50) NOT NULL,
    tipo                 character varying(50) NOT NULL,
    frota                character varying(50),
    posicao              character varying(50),
    data_evento          date,
    km_inicial           numeric(10,2) DEFAULT 0,
    km_final             numeric(10,2) DEFAULT 0,
    km_rodado            numeric(10,2) DEFAULT 0,
    mm_entrada           numeric(5,2) DEFAULT 0,
    mm_saida             numeric(5,2) DEFAULT 0,
    motivo               text,
    custo                numeric(10,2) DEFAULT 0,
    operador             character varying(100),
    criado_em            timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usuario_id           integer,
    status               character varying(20) DEFAULT 'ATIVO'::character varying,
    editado_por          integer,
    editado_em           timestamp without time zone,
    motivo_edicao        text,
    dados_antes_edicao   jsonb
);

ALTER TABLE ONLY public.movimentacoes DROP CONSTRAINT IF EXISTS movimentacoes_pkey;
ALTER TABLE ONLY public.movimentacoes ADD CONSTRAINT movimentacoes_pkey PRIMARY KEY (id_mov);

CREATE INDEX IF NOT EXISTS idx_mov_data    ON public.movimentacoes USING btree (data_evento);
CREATE INDEX IF NOT EXISTS idx_mov_fogo    ON public.movimentacoes USING btree (fogo);
CREATE INDEX IF NOT EXISTS idx_mov_frota   ON public.movimentacoes USING btree (frota);
CREATE INDEX IF NOT EXISTS idx_mov_status  ON public.movimentacoes USING btree (status);

ALTER TABLE ONLY public.movimentacoes DROP CONSTRAINT IF EXISTS movimentacoes_editado_por_fkey;
ALTER TABLE ONLY public.movimentacoes ADD CONSTRAINT movimentacoes_editado_por_fkey FOREIGN KEY (editado_por) REFERENCES public.usuarios(id);
ALTER TABLE ONLY public.movimentacoes DROP CONSTRAINT IF EXISTS movimentacoes_usuario_id_fkey;
ALTER TABLE ONLY public.movimentacoes ADD CONSTRAINT movimentacoes_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);

-- ---- vistorias ----
CREATE TABLE IF NOT EXISTS public.vistorias (
    id_vistoria            character varying(100) NOT NULL,
    data_vistoria          date,
    frota                  character varying(50),
    fogo                   character varying(50),
    posicao                character varying(50),
    km_caminhao            numeric(10,2) DEFAULT 0,
    mm_medido              numeric(5,2) DEFAULT 0,
    mm_desgastado          numeric(5,2) DEFAULT 0,
    km_rodado_ate_agora    numeric(10,2) DEFAULT 0,
    rendimento_km_mm       numeric(10,2) DEFAULT 0,
    mm_mes                 numeric(5,2) DEFAULT 0,
    responsavel            character varying(100),
    observacoes            text,
    anomalias              jsonb DEFAULT '[]'::jsonb,
    pneu_confirmado        character varying(10) DEFAULT 'SIM'::character varying,
    operador               character varying(100),
    criado_em              timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usuario_id             integer,
    perfil_no_momento      character varying(50),
    status_revisao         character varying(20) DEFAULT 'APROVADA'::character varying,
    revisado_por           integer,
    revisado_em            timestamp without time zone,
    observacao_revisao     text
);

ALTER TABLE ONLY public.vistorias DROP CONSTRAINT IF EXISTS vistorias_pkey;
ALTER TABLE ONLY public.vistorias ADD CONSTRAINT vistorias_pkey PRIMARY KEY (id_vistoria);

CREATE INDEX IF NOT EXISTS idx_vist_data            ON public.vistorias USING btree (data_vistoria);
CREATE INDEX IF NOT EXISTS idx_vist_fogo            ON public.vistorias USING btree (fogo);
CREATE INDEX IF NOT EXISTS idx_vist_frota           ON public.vistorias USING btree (frota);
CREATE INDEX IF NOT EXISTS idx_vist_status_revisao  ON public.vistorias USING btree (status_revisao);

ALTER TABLE ONLY public.vistorias DROP CONSTRAINT IF EXISTS vistorias_revisado_por_fkey;
ALTER TABLE ONLY public.vistorias ADD CONSTRAINT vistorias_revisado_por_fkey FOREIGN KEY (revisado_por) REFERENCES public.usuarios(id);
ALTER TABLE ONLY public.vistorias DROP CONSTRAINT IF EXISTS vistorias_usuario_id_fkey;
ALTER TABLE ONLY public.vistorias ADD CONSTRAINT vistorias_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


-- ============================================================================
-- 2) HISTÓRICO DE KM (conferência de frota importada por CSV/TXT)
--    Guarda só o que o painel usa: Data Emissão, Frota, Placa, Km Atual.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.historico_km (
    id            character varying(100) NOT NULL,
    data_emissao  character varying(20),
    frota         character varying(50) NOT NULL,
    placa         character varying(20),
    km_atual      character varying(20),
    nome_arquivo  character varying(150),
    operador      character varying(100),
    criado_em     timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE ONLY public.historico_km DROP CONSTRAINT IF EXISTS historico_km_pkey;
ALTER TABLE ONLY public.historico_km ADD CONSTRAINT historico_km_pkey PRIMARY KEY (id);

CREATE INDEX IF NOT EXISTS idx_historico_km_frota      ON public.historico_km USING btree (frota);
CREATE INDEX IF NOT EXISTS idx_historico_km_placa      ON public.historico_km USING btree (placa);
CREATE INDEX IF NOT EXISTS idx_historico_km_criado_em  ON public.historico_km USING btree (criado_em);


-- ============================================================================
-- 3) LOGS DE AUDITORIA (CRUD + acessos — retenção de 15 dias, visível só
--    pro administrador dentro do site)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.logs (
    id          bigserial NOT NULL,
    tipo        character varying(20)  NOT NULL,
    mensagem    character varying(255) NOT NULL,
    detalhe     text,
    operador    character varying(100),
    acao        character varying(50),
    criado_em   timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE ONLY public.logs DROP CONSTRAINT IF EXISTS logs_pkey;
ALTER TABLE ONLY public.logs ADD CONSTRAINT logs_pkey PRIMARY KEY (id);

CREATE INDEX IF NOT EXISTS idx_logs_criado_em  ON public.logs USING btree (criado_em);
CREATE INDEX IF NOT EXISTS idx_logs_operador   ON public.logs USING btree (operador);


-- ============================================================================
-- 4) ALERTAS (metas de KM, avisos de retirada, relatórios periódicos por e-mail)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.alertas (
    id               character varying(100) NOT NULL,
    nome             character varying(150) NOT NULL,
    tipo             character varying(40)  NOT NULL, -- meta_km_pneu | retirada_abaixo_km | relatorio_km | relatorio_cpk | relatorio_movimentacao
    filtro_frota     character varying(50),            -- NULL = todas as frotas
    filtro_modelo    character varying(100),           -- NULL = todos os modelos de pneu
    filtro_tipo      character varying(20),            -- NULL = todos os tipos de veiculo (TOCO/TRUCK/3-4/...)
    valor_meta       numeric(12,2),                    -- km alvo (meta_km_pneu / retirada_abaixo_km)
    periodicidade    character varying(10),            -- semanal | mensal (para os tipos de relatorio)
    email_destino    character varying(255) NOT NULL,
    ativo            boolean DEFAULT true,
    criado_por       character varying(100),
    criado_em        timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    ultima_execucao  timestamp without time zone
);

ALTER TABLE ONLY public.alertas DROP CONSTRAINT IF EXISTS alertas_pkey;
ALTER TABLE ONLY public.alertas ADD CONSTRAINT alertas_pkey PRIMARY KEY (id);

CREATE INDEX IF NOT EXISTS idx_alertas_tipo   ON public.alertas USING btree (tipo);
CREATE INDEX IF NOT EXISTS idx_alertas_ativo  ON public.alertas USING btree (ativo);

-- Log de disparos, pra nunca mandar o mesmo alerta duas vezes pro mesmo pneu/periodo.
CREATE TABLE IF NOT EXISTS public.alertas_disparos (
    id            bigserial NOT NULL,
    alerta_id     character varying(100) NOT NULL,
    fogo          character varying(50),   -- preenchido so em alertas por pneu
    referencia    character varying(50),   -- ex: "2026-W40" (semana) ou "2026-10" (mes), pra relatorios periodicos
    disparado_em  timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE ONLY public.alertas_disparos DROP CONSTRAINT IF EXISTS alertas_disparos_pkey;
ALTER TABLE ONLY public.alertas_disparos ADD CONSTRAINT alertas_disparos_pkey PRIMARY KEY (id);

CREATE INDEX IF NOT EXISTS idx_alertas_disparos_alerta ON public.alertas_disparos USING btree (alerta_id);


-- ============================================================================
-- 5) USUÁRIO ADMINISTRADOR INICIAL
--    Login "admin", senha "509470" — troque pelo próprio painel assim que
--    possível. A senha nunca fica em texto puro: é gravada com hash bcrypt
--    (pgcrypto), o mesmo esquema que o login do n8n usa pra conferir.
-- ============================================================================

INSERT INTO usuarios (nome, senha, perfil, permissoes)
VALUES ('admin', crypt('509470', gen_salt('bf')), 'administrador', '{}'::jsonb)
ON CONFLICT (nome) DO NOTHING;

-- Se você já tem uma tabela "usuarios" com senhas em TEXTO PURO (de antes
-- dessa migração), rode o comando abaixo pra re-hashear todo mundo de uma
-- vez. CUIDADO: só rode isso UMA vez — rodar de novo depois que as senhas
-- já estiverem com hash vai quebrar o login (hash do hash).
--
-- UPDATE usuarios SET senha = crypt(senha, gen_salt('bf'))
-- WHERE senha !~ '^\$2[aby]\$';

-- ============================================================================
-- FIM. Depois de rodar este arquivo, importe o GPneus.json atualizado no n8n
-- e, se quiser enviar e-mails de alerta, configure a credencial SMTP no node
-- "Enviar E-mail de Alerta".
-- ============================================================================
