<?php
declare(strict_types=1);
/**
 * FPM readiness probe — FastCGI ping (ping.path / ping.response).
 * Used by docker-php-healthcheck readiness on FPM images.
 */

const FCGI_VERSION = 1;
const FCGI_BEGIN_REQUEST = 1;
const FCGI_PARAMS = 4;
const FCGI_STDIN = 5;
const FCGI_STDOUT = 6;
const FCGI_END_REQUEST = 3;
const FCGI_RESPONDER = 1;

function fcgi_header(int $type, string $content, int $requestId = 1): string
{
    $length = strlen($content);
    $padding = (8 - ($length % 8)) % 8;

    return pack('CCnnCC', FCGI_VERSION, $type, $requestId, 0, $length, $padding)
        . $content
        . str_repeat("\0", $padding);
}

function fcgi_encode_length(int $n): string
{
    return $n < 128 ? chr($n) : pack('N', $n | 0x80000000);
}

function fcgi_encode_params(array $params): string
{
    $payload = '';
    foreach ($params as $name => $value) {
        $payload .= fcgi_encode_length(strlen($name))
            . fcgi_encode_length(strlen((string) $value))
            . $name
            . $value;
    }

    return $payload;
}

function fcgi_build_request(array $params): string
{
    $request = fcgi_header(
        FCGI_BEGIN_REQUEST,
        pack('nC', FCGI_RESPONDER, 0) . "\0\0\0\0\0"
    );

    $encoded = fcgi_encode_params($params);
    $request .= fcgi_header(FCGI_PARAMS, $encoded);
    $request .= fcgi_header(FCGI_PARAMS, '');
    $request .= fcgi_header(FCGI_STDIN, '');

    return $request;
}

function fcgi_read_stdout($socket): string
{
    $body = '';

    while (!feof($socket)) {
        $header = fread($socket, 8);
        if ($header === false || strlen($header) < 8) {
            break;
        }

        $type = ord($header[1]);
        $length = (ord($header[4]) << 8) + ord($header[5]);
        $padding = ord($header[6]);
        $content = $length > 0 ? (fread($socket, $length) ?: '') : '';

        if ($padding > 0) {
            fread($socket, $padding);
        }

        if ($type === FCGI_STDOUT) {
            $body .= $content;
        }

        if ($type === FCGI_END_REQUEST) {
            break;
        }
    }

    return $body;
}

$path = getenv('FPM_PING_PATH') ?: '/fpm-ping';
$expect = getenv('FPM_PING_RESPONSE') ?: 'pong';
$host = getenv('FPM_HEALTH_HOST') ?: '127.0.0.1';
$port = (int) (getenv('FPM_HEALTH_PORT') ?: '9000');

$socket = @fsockopen($host, $port, $errno, $errstr, 1.0);
if (!$socket) {
    fwrite(STDERR, "fpm-ping: connect failed: {$errstr} ({$errno})\n");
    exit(1);
}

stream_set_timeout($socket, 1);

$params = [
    'REQUEST_METHOD' => 'GET',
    'SCRIPT_FILENAME' => $path,
    'SCRIPT_NAME' => $path,
    'REQUEST_URI' => $path,
    'QUERY_STRING' => '',
];

fwrite($socket, fcgi_build_request($params));
$response = fcgi_read_stdout($socket);
fclose($socket);

if ($response === '' || !str_contains($response, $expect)) {
    fwrite(STDERR, "fpm-ping: expected '{$expect}', got empty or mismatched response\n");
    exit(1);
}

exit(0);
