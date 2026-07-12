#!/usr/bin/env php
<?php
declare(strict_types=1);
/**
 * docker-php-healthcheck — startup / liveness / readiness (no shell required)
 *
 * Usage:
 *   php docker-php-healthcheck.php [startup|liveness|readiness|health]
 */

$mode = $argv[1] ?? 'health';

function isFpm(): bool
{
    return is_executable('/usr/local/sbin/php-fpm');
}

function cliStartup(): int
{
    return version_compare(PHP_VERSION, '8.0', '>=') ? 0 : 1;
}

function cliReadiness(): int
{
    foreach (['curl', 'mbstring', 'openssl', 'json'] as $ext) {
        if (!extension_loaded($ext)) {
            fwrite(STDERR, "readiness: missing ext {$ext}\n");
            return 1;
        }
    }

    return 0;
}

function fpmConfigSanity(): int
{
    $config = '/usr/local/etc/php-fpm.conf';
    if (!is_readable($config)) {
        fwrite(STDERR, "startup: missing {$config}\n");
        return 1;
    }
    $body = file_get_contents($config);
    if ($body === false || str_contains($body, 'NONE/')) {
        fwrite(STDERR, "startup: invalid php-fpm.conf\n");
        return 1;
    }

    return 0;
}

function fpmLiveness(): int
{
    $pidFile = getenv('FPM_PID_FILE') ?: '/tmp/php-fpm.pid';
    if (is_readable($pidFile)) {
        $pid = (int) trim((string) file_get_contents($pidFile));
        if ($pid > 0 && function_exists('posix_kill') && @posix_kill($pid, 0)) {
            return 0;
        }
    }

    $host = getenv('FPM_HEALTH_HOST') ?: '127.0.0.1';
    $port = (int) (getenv('FPM_HEALTH_PORT') ?: '9000');
    $errno = 0;
    $errstr = '';
    $fp = @fsockopen($host, $port, $errno, $errstr, 1.0);
    if (!$fp) {
        fwrite(STDERR, "liveness: port {$port}: {$errstr} ({$errno})\n");
        return 1;
    }
    fclose($fp);

    return 0;
}

function fpmReadiness(): int
{
    $script = getenv('FPM_PING_SCRIPT') ?: '/usr/local/libexec/php/fpm-ping.php';
    if (!is_readable($script)) {
        fwrite(STDERR, "readiness: missing {$script}\n");
        return 1;
    }

    include $script;

    return 1;
}

function runFpm(string $mode): int
{
    return match ($mode) {
        'startup' => fpmConfigSanity(),
        'liveness' => fpmLiveness(),
        'readiness' => fpmReadiness(),
        'health' => fpmLiveness() === 0 && fpmReadiness() === 0 ? 0 : 1,
        default => usage($mode),
    };
}

function runCli(string $mode): int
{
    return match ($mode) {
        'startup' => cliStartup(),
        'liveness' => 0,
        'readiness', 'health' => cliReadiness(),
        default => usage($mode),
    };
}

function usage(string $mode): int
{
    fwrite(STDERR, "unknown probe: {$mode}\n");
    return 2;
}

exit(isFpm() ? runFpm($mode) : runCli($mode));
