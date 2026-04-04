<?php

$root = $argv[1] ?? '/path/to/vichan';
$board = $argv[2] ?? 'bant';
$limit = isset($argv[3]) ? max((int) $argv[3], 1) : 10;

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

$threadStmt = $pdo->prepare("SELECT id FROM `$table` WHERE thread IS NULL ORDER BY bump DESC LIMIT $limit");
$threadStmt->execute();
$threadIds = array_map('intval', $threadStmt->fetchAll(PDO::FETCH_COLUMN));

if (!$threadIds) {
    echo json_encode([
        'board' => $boardRow,
        'thread_ids' => [],
        'posts' => [],
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit(0);
}

$placeholders = implode(',', array_fill(0, count($threadIds), '?'));
$postStmt = $pdo->prepare(
    "SELECT id, thread, subject, email, name, trip, body_nomarkup, body, password, ip, sticky, locked, cycle, sage, slug, embed, time, bump, files
     FROM `$table`
     WHERE id IN ($placeholders) OR thread IN ($placeholders)
     ORDER BY COALESCE(thread, id) ASC, thread IS NULL DESC, time ASC, id ASC"
);
$postStmt->execute(array_merge($threadIds, $threadIds));
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
    'thread_ids' => $threadIds,
    'posts' => $posts,
], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
