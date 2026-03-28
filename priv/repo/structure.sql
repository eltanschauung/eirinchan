--
-- PostgreSQL database dump
--

\restrict lZVoHfvODA1T4GTCKUWyYAV6fAgaJbU38NCGMyb5KTSLB3jempQOTRNccwjnvKq

-- Dumped from database version 13.18 (Debian 13.18-0+deb11u1)
-- Dumped by pg_dump version 15.16 (Debian 15.16-0+deb12u1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: announcement_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.announcement_entries (
    id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    mod_user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: announcement_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.announcement_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: announcement_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.announcement_entries_id_seq OWNED BY public.announcement_entries.id;


--
-- Name: ban_appeals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ban_appeals (
    id bigint NOT NULL,
    ban_id bigint NOT NULL,
    body text NOT NULL,
    status character varying(255) DEFAULT 'open'::character varying NOT NULL,
    resolution_note text,
    resolved_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: ban_appeals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ban_appeals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ban_appeals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ban_appeals_id_seq OWNED BY public.ban_appeals.id;


--
-- Name: bans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bans (
    id bigint NOT NULL,
    board_id bigint,
    mod_user_id bigint,
    ip_subnet character varying(255) NOT NULL,
    reason text,
    expires_at timestamp without time zone,
    active boolean DEFAULT true NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: bans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bans_id_seq OWNED BY public.bans.id;


--
-- Name: boards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.boards (
    id bigint NOT NULL,
    uri character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    subtitle character varying(255),
    config_overrides jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    next_public_post_id integer DEFAULT 1 NOT NULL
);


--
-- Name: boards_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.boards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: boards_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.boards_id_seq OWNED BY public.boards.id;


--
-- Name: build_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.build_jobs (
    id bigint NOT NULL,
    board_id bigint NOT NULL,
    kind character varying(255) NOT NULL,
    thread_id bigint,
    status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    finished_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: build_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.build_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: build_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.build_jobs_id_seq OWNED BY public.build_jobs.id;


--
-- Name: cites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cites (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    target_post_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: cites_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cites_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cites_id_seq OWNED BY public.cites.id;


--
-- Name: custom_pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_pages (
    id bigint NOT NULL,
    slug character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    mod_user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: custom_pages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.custom_pages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: custom_pages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.custom_pages_id_seq OWNED BY public.custom_pages.id;


--
-- Name: feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feedback (
    id bigint NOT NULL,
    name character varying(255),
    email character varying(255),
    body text NOT NULL,
    ip_subnet character varying(255) NOT NULL,
    read_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: feedback_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feedback_comments (
    id bigint NOT NULL,
    feedback_id bigint NOT NULL,
    body text NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: feedback_comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.feedback_comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feedback_comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.feedback_comments_id_seq OWNED BY public.feedback_comments.id;


--
-- Name: feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.feedback_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.feedback_id_seq OWNED BY public.feedback.id;


--
-- Name: flood_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flood_entries (
    id bigint NOT NULL,
    board_id bigint NOT NULL,
    ip_subnet character varying(255) NOT NULL,
    body_hash character varying(255),
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: flood_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flood_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flood_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flood_entries_id_seq OWNED BY public.flood_entries.id;


--
-- Name: ip_access_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ip_access_entries (
    ip character varying(255) NOT NULL,
    password character varying(255),
    granted_at timestamp(0) without time zone
);


--
-- Name: ip_access_passwords; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ip_access_passwords (
    password character varying(255) NOT NULL
);


--
-- Name: ip_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ip_notes (
    id bigint NOT NULL,
    ip_subnet character varying(255) NOT NULL,
    body text NOT NULL,
    board_id bigint,
    mod_user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: ip_notes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ip_notes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ip_notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ip_notes_id_seq OWNED BY public.ip_notes.id;


--
-- Name: mod_board_accesses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mod_board_accesses (
    id bigint NOT NULL,
    mod_user_id bigint NOT NULL,
    board_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: mod_board_accesses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mod_board_accesses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mod_board_accesses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mod_board_accesses_id_seq OWNED BY public.mod_board_accesses.id;


--
-- Name: mod_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mod_messages (
    id bigint NOT NULL,
    subject character varying(255),
    body text NOT NULL,
    read_at timestamp without time zone,
    sender_id bigint NOT NULL,
    recipient_id bigint NOT NULL,
    reply_to_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: mod_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mod_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mod_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mod_messages_id_seq OWNED BY public.mod_messages.id;


--
-- Name: mod_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mod_users (
    id bigint NOT NULL,
    username character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    password_salt character varying(255) NOT NULL,
    role character varying(255) DEFAULT 'admin'::character varying NOT NULL,
    last_login_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    all_boards boolean DEFAULT false NOT NULL
);


--
-- Name: mod_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mod_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mod_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mod_users_id_seq OWNED BY public.mod_users.id;


--
-- Name: moderation_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.moderation_logs (
    id bigint NOT NULL,
    mod_user_id bigint,
    actor_ip character varying(255),
    board_uri character varying(255),
    text text NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: moderation_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.moderation_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: moderation_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.moderation_logs_id_seq OWNED BY public.moderation_logs.id;


--
-- Name: news_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.news_entries (
    id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    mod_user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: news_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.news_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: news_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.news_entries_id_seq OWNED BY public.news_entries.id;


--
-- Name: nntp_references; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nntp_references (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    target_post_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: nntp_references_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nntp_references_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nntp_references_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nntp_references_id_seq OWNED BY public.nntp_references.id;


--
-- Name: noticeboard_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.noticeboard_entries (
    id bigint NOT NULL,
    subject character varying(255),
    body_html text NOT NULL,
    author_name character varying(255) NOT NULL,
    posted_at timestamp without time zone NOT NULL,
    mod_user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: noticeboard_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.noticeboard_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: noticeboard_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.noticeboard_entries_id_seq OWNED BY public.noticeboard_entries.id;


--
-- Name: post_failure_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_failure_logs (
    id bigint NOT NULL,
    event character varying(255) NOT NULL,
    level character varying(255) NOT NULL,
    board_uri character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: post_failure_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.post_failure_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: post_failure_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.post_failure_logs_id_seq OWNED BY public.post_failure_logs.id;


--
-- Name: post_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_files (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    "position" integer NOT NULL,
    file_name character varying(255) NOT NULL,
    file_path character varying(255) NOT NULL,
    thumb_path character varying(255),
    file_size integer,
    file_type character varying(255) NOT NULL,
    file_md5 character varying(255) NOT NULL,
    image_width integer,
    image_height integer,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    spoiler boolean DEFAULT false NOT NULL
);


--
-- Name: post_files_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.post_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: post_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.post_files_id_seq OWNED BY public.post_files.id;


--
-- Name: post_ownerships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_ownerships (
    id bigint NOT NULL,
    browser_token character varying(255) NOT NULL,
    post_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: post_ownerships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.post_ownerships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: post_ownerships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.post_ownerships_id_seq OWNED BY public.post_ownerships.id;


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id bigint NOT NULL,
    board_id bigint NOT NULL,
    thread_id bigint,
    name character varying(255),
    email character varying(255),
    subject character varying(255),
    password character varying(255),
    body text NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    bump_at timestamp without time zone,
    sticky boolean DEFAULT false NOT NULL,
    locked boolean DEFAULT false NOT NULL,
    cycle boolean DEFAULT false NOT NULL,
    sage boolean DEFAULT false NOT NULL,
    slug character varying(255),
    file_name character varying(255),
    file_path character varying(255),
    file_size integer,
    file_type character varying(255),
    file_md5 character varying(255),
    thumb_path character varying(255),
    image_width integer,
    image_height integer,
    spoiler boolean DEFAULT false NOT NULL,
    flag_codes character varying(255)[] DEFAULT ARRAY[]::character varying[],
    flag_alts character varying(255)[] DEFAULT ARRAY[]::character varying[],
    tag character varying(255),
    proxy character varying(255),
    tripcode character varying(255),
    capcode character varying(255),
    raw_html boolean DEFAULT false NOT NULL,
    ip_subnet character varying(255),
    embed text,
    public_id integer NOT NULL,
    legacy_import_id integer,
    cached_reply_count integer DEFAULT 0 NOT NULL,
    cached_image_count integer DEFAULT 0 NOT NULL,
    cached_last_reply_at timestamp without time zone
);


--
-- Name: posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posts_id_seq OWNED BY public.posts.id;


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id bigint NOT NULL,
    board_id bigint NOT NULL,
    post_id bigint NOT NULL,
    thread_id bigint NOT NULL,
    reason text NOT NULL,
    dismissed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    ip character varying(255)
);


--
-- Name: reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reports_id_seq OWNED BY public.reports.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: search_queries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.search_queries (
    id bigint NOT NULL,
    board_id bigint,
    ip_subnet character varying(255) NOT NULL,
    query character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: search_queries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.search_queries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: search_queries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.search_queries_id_seq OWNED BY public.search_queries.id;


--
-- Name: thread_watches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.thread_watches (
    id bigint NOT NULL,
    browser_token character varying(255) NOT NULL,
    board_uri character varying(255) NOT NULL,
    thread_id integer NOT NULL,
    last_seen_post_id integer,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: thread_watches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.thread_watches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: thread_watches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.thread_watches_id_seq OWNED BY public.thread_watches.id;


--
-- Name: announcement_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcement_entries ALTER COLUMN id SET DEFAULT nextval('public.announcement_entries_id_seq'::regclass);


--
-- Name: ban_appeals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ban_appeals ALTER COLUMN id SET DEFAULT nextval('public.ban_appeals_id_seq'::regclass);


--
-- Name: bans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bans ALTER COLUMN id SET DEFAULT nextval('public.bans_id_seq'::regclass);


--
-- Name: boards id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boards ALTER COLUMN id SET DEFAULT nextval('public.boards_id_seq'::regclass);


--
-- Name: build_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_jobs ALTER COLUMN id SET DEFAULT nextval('public.build_jobs_id_seq'::regclass);


--
-- Name: cites id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cites ALTER COLUMN id SET DEFAULT nextval('public.cites_id_seq'::regclass);


--
-- Name: custom_pages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_pages ALTER COLUMN id SET DEFAULT nextval('public.custom_pages_id_seq'::regclass);


--
-- Name: feedback id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback ALTER COLUMN id SET DEFAULT nextval('public.feedback_id_seq'::regclass);


--
-- Name: feedback_comments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_comments ALTER COLUMN id SET DEFAULT nextval('public.feedback_comments_id_seq'::regclass);


--
-- Name: flood_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flood_entries ALTER COLUMN id SET DEFAULT nextval('public.flood_entries_id_seq'::regclass);


--
-- Name: ip_notes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ip_notes ALTER COLUMN id SET DEFAULT nextval('public.ip_notes_id_seq'::regclass);


--
-- Name: mod_board_accesses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_board_accesses ALTER COLUMN id SET DEFAULT nextval('public.mod_board_accesses_id_seq'::regclass);


--
-- Name: mod_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_messages ALTER COLUMN id SET DEFAULT nextval('public.mod_messages_id_seq'::regclass);


--
-- Name: mod_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_users ALTER COLUMN id SET DEFAULT nextval('public.mod_users_id_seq'::regclass);


--
-- Name: moderation_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_logs ALTER COLUMN id SET DEFAULT nextval('public.moderation_logs_id_seq'::regclass);


--
-- Name: news_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.news_entries ALTER COLUMN id SET DEFAULT nextval('public.news_entries_id_seq'::regclass);


--
-- Name: nntp_references id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nntp_references ALTER COLUMN id SET DEFAULT nextval('public.nntp_references_id_seq'::regclass);


--
-- Name: noticeboard_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.noticeboard_entries ALTER COLUMN id SET DEFAULT nextval('public.noticeboard_entries_id_seq'::regclass);


--
-- Name: post_failure_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_failure_logs ALTER COLUMN id SET DEFAULT nextval('public.post_failure_logs_id_seq'::regclass);


--
-- Name: post_files id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_files ALTER COLUMN id SET DEFAULT nextval('public.post_files_id_seq'::regclass);


--
-- Name: post_ownerships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_ownerships ALTER COLUMN id SET DEFAULT nextval('public.post_ownerships_id_seq'::regclass);


--
-- Name: posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts ALTER COLUMN id SET DEFAULT nextval('public.posts_id_seq'::regclass);


--
-- Name: reports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports ALTER COLUMN id SET DEFAULT nextval('public.reports_id_seq'::regclass);


--
-- Name: search_queries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_queries ALTER COLUMN id SET DEFAULT nextval('public.search_queries_id_seq'::regclass);


--
-- Name: thread_watches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thread_watches ALTER COLUMN id SET DEFAULT nextval('public.thread_watches_id_seq'::regclass);


--
-- Name: announcement_entries announcement_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcement_entries
    ADD CONSTRAINT announcement_entries_pkey PRIMARY KEY (id);


--
-- Name: ban_appeals ban_appeals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ban_appeals
    ADD CONSTRAINT ban_appeals_pkey PRIMARY KEY (id);


--
-- Name: bans bans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bans
    ADD CONSTRAINT bans_pkey PRIMARY KEY (id);


--
-- Name: boards boards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boards
    ADD CONSTRAINT boards_pkey PRIMARY KEY (id);


--
-- Name: build_jobs build_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_jobs
    ADD CONSTRAINT build_jobs_pkey PRIMARY KEY (id);


--
-- Name: cites cites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cites
    ADD CONSTRAINT cites_pkey PRIMARY KEY (id);


--
-- Name: custom_pages custom_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_pages
    ADD CONSTRAINT custom_pages_pkey PRIMARY KEY (id);


--
-- Name: feedback_comments feedback_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_comments
    ADD CONSTRAINT feedback_comments_pkey PRIMARY KEY (id);


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);


--
-- Name: flood_entries flood_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flood_entries
    ADD CONSTRAINT flood_entries_pkey PRIMARY KEY (id);


--
-- Name: ip_notes ip_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ip_notes
    ADD CONSTRAINT ip_notes_pkey PRIMARY KEY (id);


--
-- Name: mod_board_accesses mod_board_accesses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_board_accesses
    ADD CONSTRAINT mod_board_accesses_pkey PRIMARY KEY (id);


--
-- Name: mod_messages mod_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_messages
    ADD CONSTRAINT mod_messages_pkey PRIMARY KEY (id);


--
-- Name: mod_users mod_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_users
    ADD CONSTRAINT mod_users_pkey PRIMARY KEY (id);


--
-- Name: moderation_logs moderation_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_logs
    ADD CONSTRAINT moderation_logs_pkey PRIMARY KEY (id);


--
-- Name: news_entries news_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.news_entries
    ADD CONSTRAINT news_entries_pkey PRIMARY KEY (id);


--
-- Name: nntp_references nntp_references_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nntp_references
    ADD CONSTRAINT nntp_references_pkey PRIMARY KEY (id);


--
-- Name: noticeboard_entries noticeboard_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.noticeboard_entries
    ADD CONSTRAINT noticeboard_entries_pkey PRIMARY KEY (id);


--
-- Name: post_failure_logs post_failure_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_failure_logs
    ADD CONSTRAINT post_failure_logs_pkey PRIMARY KEY (id);


--
-- Name: post_files post_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_files
    ADD CONSTRAINT post_files_pkey PRIMARY KEY (id);


--
-- Name: post_ownerships post_ownerships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_ownerships
    ADD CONSTRAINT post_ownerships_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: search_queries search_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_queries
    ADD CONSTRAINT search_queries_pkey PRIMARY KEY (id);


--
-- Name: thread_watches thread_watches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thread_watches
    ADD CONSTRAINT thread_watches_pkey PRIMARY KEY (id);


--
-- Name: announcement_entries_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX announcement_entries_updated_at_index ON public.announcement_entries USING btree (updated_at);


--
-- Name: ban_appeals_ban_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ban_appeals_ban_id_index ON public.ban_appeals USING btree (ban_id);


--
-- Name: ban_appeals_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ban_appeals_status_index ON public.ban_appeals USING btree (status);


--
-- Name: bans_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bans_active_index ON public.bans USING btree (active);


--
-- Name: bans_board_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bans_board_id_index ON public.bans USING btree (board_id);


--
-- Name: bans_ip_subnet_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bans_ip_subnet_index ON public.bans USING btree (ip_subnet);


--
-- Name: boards_uri_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX boards_uri_index ON public.boards USING btree (uri);


--
-- Name: build_jobs_board_id_status_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX build_jobs_board_id_status_inserted_at_index ON public.build_jobs USING btree (board_id, status, inserted_at);


--
-- Name: cites_post_id_target_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cites_post_id_target_post_id_index ON public.cites USING btree (post_id, target_post_id);


--
-- Name: cites_target_post_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cites_target_post_id_idx ON public.cites USING btree (target_post_id);


--
-- Name: custom_pages_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX custom_pages_slug_index ON public.custom_pages USING btree (slug);


--
-- Name: feedback_comments_feedback_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX feedback_comments_feedback_id_inserted_at_index ON public.feedback_comments USING btree (feedback_id, inserted_at);


--
-- Name: feedback_read_at_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX feedback_read_at_inserted_at_index ON public.feedback USING btree (read_at, inserted_at);


--
-- Name: flood_entries_board_id_ip_subnet_body_hash_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flood_entries_board_id_ip_subnet_body_hash_inserted_at_index ON public.flood_entries USING btree (board_id, ip_subnet, body_hash, inserted_at);


--
-- Name: flood_entries_board_id_ip_subnet_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flood_entries_board_id_ip_subnet_inserted_at_index ON public.flood_entries USING btree (board_id, ip_subnet, inserted_at);


--
-- Name: ip_access_entries_ip_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ip_access_entries_ip_index ON public.ip_access_entries USING btree (ip);


--
-- Name: ip_access_passwords_password_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ip_access_passwords_password_index ON public.ip_access_passwords USING btree (password);


--
-- Name: ip_notes_board_id_ip_subnet_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ip_notes_board_id_ip_subnet_inserted_at_index ON public.ip_notes USING btree (board_id, ip_subnet, inserted_at);


--
-- Name: ip_notes_ip_subnet_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ip_notes_ip_subnet_inserted_at_index ON public.ip_notes USING btree (ip_subnet, inserted_at);


--
-- Name: mod_board_accesses_board_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mod_board_accesses_board_id_index ON public.mod_board_accesses USING btree (board_id);


--
-- Name: mod_board_accesses_mod_user_id_board_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mod_board_accesses_mod_user_id_board_id_index ON public.mod_board_accesses USING btree (mod_user_id, board_id);


--
-- Name: mod_messages_recipient_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mod_messages_recipient_id_inserted_at_index ON public.mod_messages USING btree (recipient_id, inserted_at);


--
-- Name: mod_messages_reply_to_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mod_messages_reply_to_id_index ON public.mod_messages USING btree (reply_to_id);


--
-- Name: mod_messages_sender_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mod_messages_sender_id_inserted_at_index ON public.mod_messages USING btree (sender_id, inserted_at);


--
-- Name: mod_users_username_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mod_users_username_index ON public.mod_users USING btree (username);


--
-- Name: moderation_logs_board_uri_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX moderation_logs_board_uri_inserted_at_index ON public.moderation_logs USING btree (board_uri, inserted_at);


--
-- Name: moderation_logs_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX moderation_logs_inserted_at_index ON public.moderation_logs USING btree (inserted_at);


--
-- Name: moderation_logs_mod_user_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX moderation_logs_mod_user_id_inserted_at_index ON public.moderation_logs USING btree (mod_user_id, inserted_at);


--
-- Name: news_entries_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX news_entries_inserted_at_index ON public.news_entries USING btree (inserted_at);


--
-- Name: news_entries_mod_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX news_entries_mod_user_id_index ON public.news_entries USING btree (mod_user_id);


--
-- Name: nntp_references_post_id_target_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX nntp_references_post_id_target_post_id_index ON public.nntp_references USING btree (post_id, target_post_id);


--
-- Name: nntp_references_target_post_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nntp_references_target_post_id_idx ON public.nntp_references USING btree (target_post_id);


--
-- Name: noticeboard_entries_posted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX noticeboard_entries_posted_at_index ON public.noticeboard_entries USING btree (posted_at);


--
-- Name: post_failure_logs_board_uri_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_failure_logs_board_uri_index ON public.post_failure_logs USING btree (board_uri);


--
-- Name: post_failure_logs_event_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_failure_logs_event_index ON public.post_failure_logs USING btree (event);


--
-- Name: post_failure_logs_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_failure_logs_inserted_at_index ON public.post_failure_logs USING btree (inserted_at);


--
-- Name: post_files_post_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_files_post_id_position_index ON public.post_files USING btree (post_id, "position");


--
-- Name: post_ownerships_browser_token_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX post_ownerships_browser_token_post_id_index ON public.post_ownerships USING btree (browser_token, post_id);


--
-- Name: post_ownerships_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_ownerships_post_id_index ON public.post_ownerships USING btree (post_id);


--
-- Name: posts_board_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_board_id_inserted_at_index ON public.posts USING btree (board_id, inserted_at);


--
-- Name: posts_board_id_ip_subnet_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_board_id_ip_subnet_inserted_at_index ON public.posts USING btree (board_id, ip_subnet, inserted_at);


--
-- Name: posts_board_id_legacy_import_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX posts_board_id_legacy_import_id_index ON public.posts USING btree (board_id, legacy_import_id) WHERE (legacy_import_id IS NOT NULL);


--
-- Name: posts_board_id_public_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX posts_board_id_public_id_index ON public.posts USING btree (board_id, public_id);


--
-- Name: posts_board_id_sticky_bump_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_board_id_sticky_bump_at_index ON public.posts USING btree (board_id, sticky, bump_at);


--
-- Name: posts_board_id_thread_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_board_id_thread_id_inserted_at_index ON public.posts USING btree (board_id, thread_id, inserted_at);


--
-- Name: posts_board_thread_listing_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_board_thread_listing_idx ON public.posts USING btree (board_id, sticky DESC, bump_at DESC, inserted_at DESC, id DESC) WHERE (thread_id IS NULL);


--
-- Name: posts_ip_subnet_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_ip_subnet_index ON public.posts USING btree (ip_subnet);


--
-- Name: reports_board_id_dismissed_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_board_id_dismissed_at_index ON public.reports USING btree (board_id, dismissed_at);


--
-- Name: reports_board_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_board_id_inserted_at_index ON public.reports USING btree (board_id, inserted_at);


--
-- Name: reports_ip_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_ip_index ON public.reports USING btree (ip);


--
-- Name: reports_post_reason_dismissed_unique_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reports_post_reason_dismissed_unique_index ON public.reports USING btree (post_id, reason, dismissed_at);


--
-- Name: search_queries_board_id_ip_subnet_query_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX search_queries_board_id_ip_subnet_query_inserted_at_index ON public.search_queries USING btree (board_id, ip_subnet, query, inserted_at);


--
-- Name: search_queries_ip_subnet_query_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX search_queries_ip_subnet_query_inserted_at_index ON public.search_queries USING btree (ip_subnet, query, inserted_at);


--
-- Name: thread_watches_board_uri_thread_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX thread_watches_board_uri_thread_id_index ON public.thread_watches USING btree (board_uri, thread_id);


--
-- Name: thread_watches_browser_token_board_uri_thread_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX thread_watches_browser_token_board_uri_thread_id_index ON public.thread_watches USING btree (browser_token, board_uri, thread_id);


--
-- Name: thread_watches_browser_token_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX thread_watches_browser_token_updated_at_index ON public.thread_watches USING btree (browser_token, updated_at);


--
-- Name: announcement_entries announcement_entries_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcement_entries
    ADD CONSTRAINT announcement_entries_mod_user_id_fkey FOREIGN KEY (mod_user_id) REFERENCES public.mod_users(id) ON DELETE SET NULL;


--
-- Name: ban_appeals ban_appeals_ban_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ban_appeals
    ADD CONSTRAINT ban_appeals_ban_id_fkey FOREIGN KEY (ban_id) REFERENCES public.bans(id) ON DELETE CASCADE;


--
-- Name: bans bans_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bans
    ADD CONSTRAINT bans_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.boards(id) ON DELETE CASCADE;


--
-- Name: bans bans_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bans
    ADD CONSTRAINT bans_mod_user_id_fkey FOREIGN KEY (mod_user_id) REFERENCES public.mod_users(id) ON DELETE SET NULL;


--
-- Name: build_jobs build_jobs_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_jobs
    ADD CONSTRAINT build_jobs_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.boards(id) ON DELETE CASCADE;


--
-- Name: cites cites_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cites
    ADD CONSTRAINT cites_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: cites cites_target_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cites
    ADD CONSTRAINT cites_target_post_id_fkey FOREIGN KEY (target_post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: custom_pages custom_pages_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_pages
    ADD CONSTRAINT custom_pages_mod_user_id_fkey FOREIGN KEY (mod_user_id) REFERENCES public.mod_users(id) ON DELETE SET NULL;


--
-- Name: feedback_comments feedback_comments_feedback_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_comments
    ADD CONSTRAINT feedback_comments_feedback_id_fkey FOREIGN KEY (feedback_id) REFERENCES public.feedback(id) ON DELETE CASCADE;


--
-- Name: flood_entries flood_entries_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flood_entries
    ADD CONSTRAINT flood_entries_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.boards(id) ON DELETE CASCADE;


--
-- Name: ip_notes ip_notes_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ip_notes
    ADD CONSTRAINT ip_notes_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.boards(id) ON DELETE CASCADE;


--
-- Name: ip_notes ip_notes_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ip_notes
    ADD CONSTRAINT ip_notes_mod_user_id_fkey FOREIGN KEY (mod_user_id) REFERENCES public.mod_users(id) ON DELETE SET NULL;


--
-- Name: mod_board_accesses mod_board_accesses_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_board_accesses
    ADD CONSTRAINT mod_board_accesses_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.boards(id) ON DELETE CASCADE;


--
-- Name: mod_board_accesses mod_board_accesses_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_board_accesses
    ADD CONSTRAINT mod_board_accesses_mod_user_id_fkey FOREIGN KEY (mod_user_id) REFERENCES public.mod_users(id) ON DELETE CASCADE;


--
-- Name: mod_messages mod_messages_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_messages
    ADD CONSTRAINT mod_messages_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.mod_users(id) ON DELETE CASCADE;


--
-- Name: mod_messages mod_messages_reply_to_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_messages
    ADD CONSTRAINT mod_messages_reply_to_id_fkey FOREIGN KEY (reply_to_id) REFERENCES public.mod_messages(id) ON DELETE SET NULL;


--
-- Name: mod_messages mod_messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mod_messages
    ADD CONSTRAINT mod_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.mod_users(id) ON DELETE CASCADE;


--
-- Name: moderation_logs moderation_logs_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_logs
    ADD CONSTRAINT moderation_logs_mod_user_id_fkey FOREIGN KEY (mod_user_id) REFERENCES public.mod_users(id) ON DELETE SET NULL;


--
-- Name: news_entries news_entries_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.news_entries
    ADD CONSTRAINT news_entries_mod_user_id_fkey FOREIGN KEY (mod_user_id) REFERENCES public.mod_users(id) ON DELETE SET NULL;


--
-- Name: nntp_references nntp_references_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nntp_references
    ADD CONSTRAINT nntp_references_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: nntp_references nntp_references_target_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nntp_references
    ADD CONSTRAINT nntp_references_target_post_id_fkey FOREIGN KEY (target_post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: noticeboard_entries noticeboard_entries_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.noticeboard_entries
    ADD CONSTRAINT noticeboard_entries_mod_user_id_fkey FOREIGN KEY (mod_user_id) REFERENCES public.mod_users(id) ON DELETE SET NULL;


--
-- Name: post_files post_files_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_files
    ADD CONSTRAINT post_files_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: post_ownerships post_ownerships_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_ownerships
    ADD CONSTRAINT post_ownerships_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: posts posts_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.boards(id) ON DELETE CASCADE;


--
-- Name: posts posts_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: reports reports_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.boards(id) ON DELETE CASCADE;


--
-- Name: reports reports_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: reports reports_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: search_queries search_queries_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_queries
    ADD CONSTRAINT search_queries_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.boards(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict lZVoHfvODA1T4GTCKUWyYAV6fAgaJbU38NCGMyb5KTSLB3jempQOTRNccwjnvKq

INSERT INTO public."schema_migrations" (version) VALUES (20260307000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307010000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307020000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307030000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307040000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307050000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307060000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307070000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307080000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307090000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307110000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307150000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307160000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307170000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307180000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307190000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307200000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307210000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307220000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307230000);
INSERT INTO public."schema_migrations" (version) VALUES (20260308000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260308010000);
INSERT INTO public."schema_migrations" (version) VALUES (20260308020000);
INSERT INTO public."schema_migrations" (version) VALUES (20260313123000);
INSERT INTO public."schema_migrations" (version) VALUES (20260314120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260319180000);
INSERT INTO public."schema_migrations" (version) VALUES (20260319193000);
INSERT INTO public."schema_migrations" (version) VALUES (20260319194500);
INSERT INTO public."schema_migrations" (version) VALUES (20260325190000);
INSERT INTO public."schema_migrations" (version) VALUES (20260325193000);
INSERT INTO public."schema_migrations" (version) VALUES (20260327120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260327184500);
