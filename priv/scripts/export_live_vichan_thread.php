<?php

$root = $argv[1] ?? '/var/www/bantculture.com/vichan';
$board = $argv[2] ?? 'bant';
$threadId = isset($argv[3]) ? max((int) $argv[3], 0) : 0;

if ($threadId <= 0) {
    fwrite(STDERR, "missing thread id\n");
    exit(1);
}

$config = ['db' => []];

if (file_exists($root . '/inc/secrets.php')) {
    require $root . '/inc/secrets.php';
}

if (empty($config['db']['server']) || empty($config['db']['database']) || empty($config['db']['user'])) {
    fwrite(STDERR, "missing live vichan db config\n");
    exit(1);
}

$dsn = 'mysql:host=' . $config['db']['server'] . ';dbname=' . $config['db']['database'] . ';charset=utf8mb4';
$pdo = new PDO($dsn, $config['db']['user'], $config['db']['password'], [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);

$table = 'posts_' . preg_replace('/[^a-zA-Z0-9_]/', '', $board);

$boardStmt = $pdo->prepare('SELECT uri, title, subtitle FROM boards WHERE uri = ? LIMIT 1');
$boardStmt->execute([$board]);
$boardRow = $boardStmt->fetch();

if (!$boardRow) {
    fwrite(STDERR, "board not found\n");
    exit(1);
}

$opStmt = $pdo->prepare("SELECT id FROM `$table` WHERE id = ? AND thread IS NULL LIMIT 1");
$opStmt->execute([$threadId]);

if (!$opStmt->fetchColumn()) {
    fwrite(STDERR, "thread not found\n");
    exit(1);
}

$postStmt = $pdo->prepare(
    "SELECT id, thread, subject, email, name, trip, body_nomarkup, body, password, ip, sticky, locked, cycle, sage, slug, embed, time, bump, files
     FROM `$table`
     WHERE id = ? OR thread = ?
     ORDER BY thread IS NULL DESC, time ASC, id ASC"
);
$postStmt->execute([$threadId, $threadId]);
$posts = [];

foreach ($postStmt->fetchAll() as $row) {
    $row['id'] = (int) $row['id'];
    $row['thread'] = $row['thread'] === null ? null : (int) $row['thread'];
    $row['sticky'] = (int) $row['sticky'];
    $row['locked'] = (int) $row['locked'];
    $row['cycle'] = (int) $row['cycle'];
    $row['sage'] = (int) $row['sage'];
    $row['time'] = (int) $row['time'];
    $row['bump'] = $row['bump'] === null ? null : (int) $row['bump'];
    $row['files'] = $row['files'] ? (json_decode($row['files'], true) ?: []) : [];
    $posts[] = $row;
}

echo json_encode([
    'board' => $boardRow,
    'thread_ids' => [$threadId],
    'posts' => $posts,
], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
