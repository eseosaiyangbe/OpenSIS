<?php
error_reporting(0);
ini_set('display_errors', '0');

session_start();

include 'lang/supportedLanguages.php';

if (isset($_REQUEST['language']) && in_array($_REQUEST['language'], array_keys($supportedLanguages), true)) {
    $langCode2 = $_REQUEST['language'];
} elseif (isset($_COOKIE['remember_me_lang']) && in_array($_COOKIE['remember_me_lang'], array_keys($supportedLanguages), true)) {
    $langCode2 = $_COOKIE['remember_me_lang'];
} elseif (!empty($_SESSION['language']) && in_array($_SESSION['language'], array_keys($supportedLanguages), true)) {
    $langCode2 = $_SESSION['language'];
} else {
    $langCode2 = 'en';
}

$_SESSION['language'] = $langCode2;
include "lang/lang_" . $_SESSION['language'] . ".php";

function public_registration_value($key)
{
    return htmlspecialchars($_POST[$key] ?? '', ENT_QUOTES, 'UTF-8');
}

function public_registration_parse_secrets_file()
{
    $path = getenv('APP_SECRETS_FILE') ?: '/run/secrets/app.env';
    $values = array();

    if (!is_readable($path)) {
        return $values;
    }

    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if ($line === '' || $line[0] === '#') {
            continue;
        }

        $parts = explode('=', $line, 2);
        if (count($parts) !== 2) {
            continue;
        }

        $values[trim($parts[0])] = trim($parts[1]);
    }

    return $values;
}

function public_registration_config($key)
{
    static $file_values = null;

    $env_value = getenv($key);
    if ($env_value !== false && $env_value !== '') {
        return $env_value;
    }

    if ($file_values === null) {
        $file_values = public_registration_parse_secrets_file();
    }

    return $file_values[$key] ?? null;
}

function public_registration_connect()
{
    $host = public_registration_config('DB_HOST');
    $port = public_registration_config('DB_PORT') ?: '3306';
    $database = public_registration_config('MYSQL_DATABASE');
    $username = public_registration_config('MYSQL_USER');
    $password = public_registration_config('MYSQL_PASSWORD');

    if (!$host || !$database || !$username) {
        return null;
    }

    mysqli_report(MYSQLI_REPORT_OFF);
    $connection = mysqli_init();

    if (!$connection) {
        return null;
    }

    if (!mysqli_real_connect($connection, $host, $username, $password, $database, (int) $port)) {
        return null;
    }

    mysqli_set_charset($connection, 'utf8');

    return $connection;
}

function public_registration_installation_ready()
{
    return file_exists(__DIR__ . '/Data.php');
}

function public_registration_fetch_schools($connection)
{
    $schools = array();
    $statement = mysqli_prepare($connection, 'SELECT id, title FROM schools ORDER BY title');

    if (!$statement) {
        return $schools;
    }

    mysqli_stmt_execute($statement);
    mysqli_stmt_bind_result($statement, $school_id, $school_title);

    while (mysqli_stmt_fetch($statement)) {
        $schools[] = array(
            'ID' => $school_id,
            'TITLE' => $school_title,
        );
    }

    mysqli_stmt_close($statement);

    return $schools;
}

function public_registration_record_exists($connection, $sql, $types, ...$params)
{
    $statement = mysqli_prepare($connection, $sql);

    if (!$statement) {
        return false;
    }

    mysqli_stmt_bind_param($statement, $types, ...$params);
    mysqli_stmt_execute($statement);
    mysqli_stmt_store_result($statement);
    $exists = mysqli_stmt_num_rows($statement) > 0;
    mysqli_stmt_close($statement);

    return $exists;
}

if (empty($_SESSION['public_registration_token'])) {
    $_SESSION['public_registration_token'] = bin2hex(random_bytes(32));
}

if (!public_registration_installation_ready()) {
    header('Location: install/index.php');
    exit;
}

$errors = array();
$selected_school_id = $_POST['school_id'] ?? '';
$connection = public_registration_connect();
$schools = $connection ? public_registration_fetch_schools($connection) : array();

if (!$connection) {
    $errors[] = 'Registration is temporarily unavailable. Please contact school administration.';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['register_submit']) && $connection) {
    $token = $_POST['registration_token'] ?? '';

    if (!hash_equals($_SESSION['public_registration_token'] ?? '', $token)) {
        $errors[] = _pleaseTryAgain . '.';
    } else {
        $selected_school_id = trim($_POST['school_id'] ?? '');
        $first_name = trim($_POST['first_name'] ?? '');
        $last_name = trim($_POST['last_name'] ?? '');
        $email = trim($_POST['email'] ?? '');
        $username = trim($_POST['username'] ?? '');
        $password = $_POST['password'] ?? '';
        $confirm_password = $_POST['confirm_password'] ?? '';

        if ($selected_school_id === '') {
            $errors[] = 'School selection is required.';
        }

        if ($first_name === '') {
            $errors[] = 'First name is required.';
        }

        if ($last_name === '') {
            $errors[] = 'Last name is required.';
        }

        if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $errors[] = 'A valid email address is required.';
        }

        if ($username === '' || !preg_match('/^[A-Za-z0-9._-]{4,64}$/', $username)) {
            $errors[] = 'Username must be 4 to 64 characters and may include letters, numbers, dots, underscores, or hyphens.';
        }

        if (strlen($password) < 8) {
            $errors[] = 'Password must be at least 8 characters long.';
        }

        if ($password !== $confirm_password) {
            $errors[] = 'Password confirmation does not match.';
        }

        if (empty($errors) && !public_registration_record_exists($connection, 'SELECT id FROM schools WHERE id = ?', 'i', $selected_school_id)) {
            $errors[] = 'Selected school is invalid.';
        }

        if (empty($errors) && public_registration_record_exists($connection, 'SELECT id FROM login_authentication WHERE UPPER(username) = UPPER(?)', 's', $username)) {
            $errors[] = 'That username is already in use.';
        }

        if (empty($errors) && public_registration_record_exists($connection, "SELECT staff_id FROM people WHERE LOWER(email) = LOWER(?) AND profile = 'parent'", 's', $email)) {
            $errors[] = 'An account request already exists for that email address.';
        }

        if (empty($errors)) {
            $created = false;
            $password_hash = password_hash($password, PASSWORD_DEFAULT);

            mysqli_begin_transaction($connection);

            try {
                $people_statement = mysqli_prepare(
                    $connection,
                    "INSERT INTO people (current_school_id, first_name, last_name, email, profile, profile_id, is_disable)
                     VALUES (?, ?, ?, ?, 'parent', 4, 'Y')"
                );

                if (!$people_statement) {
                    throw new Exception('Unable to prepare people insert.');
                }

                mysqli_stmt_bind_param($people_statement, 'isss', $selected_school_id, $first_name, $last_name, $email);
                mysqli_stmt_execute($people_statement);
                $person_id = mysqli_insert_id($connection);
                mysqli_stmt_close($people_statement);

                if (!$person_id) {
                    throw new Exception('Unable to create the registration request.');
                }

                $auth_statement = mysqli_prepare(
                    $connection,
                    'INSERT INTO login_authentication (user_id, profile_id, username, password) VALUES (?, 4, ?, ?)'
                );

                if (!$auth_statement) {
                    throw new Exception('Unable to prepare authentication insert.');
                }

                mysqli_stmt_bind_param($auth_statement, 'iss', $person_id, $username, $password_hash);
                mysqli_stmt_execute($auth_statement);
                mysqli_stmt_close($auth_statement);

                mysqli_commit($connection);
                $created = true;
            } catch (Exception $exception) {
                mysqli_rollback($connection);
                $errors[] = 'We could not submit the registration request. Please try again.';
            }

            if ($created) {
                $_SESSION['public_registration_notice'] = _yourAccountHasBeenCreated . '. ' . _youWillBeNotifiedByEmailWhenItIsVerifiedBySchoolAdministrationAndYouCanLogIn . '.';
                $_SESSION['public_registration_token'] = bin2hex(random_bytes(32));
                header('Location: index.php?language=' . urlencode($langCode2));
                exit;
            }
        }
    }
}

?>
<!DOCTYPE html>
<html lang="en" dir="<?php echo function_exists('langDirection') && langDirection() === 'rtl' ? 'rtl' : 'ltr'; ?>">
<head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>openSIS Student Information System</title>
    <link rel="shortcut icon" href="favicon.ico">
    <meta http-equiv="Content-type" content="text/html;charset=UTF-8">
    <link href="assets/css/icons/icomoon/styles.css" rel="stylesheet" type="text/css">
    <link rel="stylesheet" type="text/css" href="assets/css/bootstrap.min.css">
    <link rel="stylesheet" type="text/css" href="assets/css/login.css">
    <style type="text/css">
        .registration-shell {
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 40px 16px;
            background:
                radial-gradient(circle at top, rgba(94, 234, 212, 0.24), rgba(94, 234, 212, 0) 34%),
                linear-gradient(135deg, #0f4c81 0%, #2f80c2 48%, #8aa1b1 100%);
        }

        .registration-card {
            width: 100%;
            max-width: 920px;
            border-radius: 24px;
            overflow: hidden;
            box-shadow: 0 24px 70px rgba(15, 23, 42, 0.24);
            background: rgba(255, 255, 255, 0.96);
        }

        .registration-sidebar {
            background: linear-gradient(160deg, rgba(15, 76, 129, 0.97) 0%, rgba(41, 128, 185, 0.92) 100%);
            color: #fff;
            padding: 36px 30px;
            height: 100%;
        }

        .registration-sidebar img {
            max-width: 160px;
            margin-bottom: 22px;
        }

        .registration-sidebar h1 {
            margin: 0 0 12px;
            font-size: 30px;
            font-weight: 700;
            letter-spacing: -0.02em;
        }

        .registration-sidebar p {
            font-size: 15px;
            line-height: 1.7;
            color: rgba(255, 255, 255, 0.88);
        }

        .registration-note {
            margin-top: 24px;
            padding: 18px 20px;
            border-radius: 16px;
            background: rgba(255, 255, 255, 0.12);
            color: rgba(255, 255, 255, 0.92);
            font-size: 14px;
            line-height: 1.6;
        }

        .registration-body {
            padding: 36px 34px;
        }

        .registration-body h2 {
            margin: 0 0 10px;
            font-size: 30px;
            font-weight: 700;
            color: #0f172a;
        }

        .registration-body p.lead-copy {
            margin-bottom: 26px;
            color: #475569;
            font-size: 15px;
            line-height: 1.7;
        }

        .registration-actions {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 16px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }

        .registration-back-link {
            color: #1565c0;
            font-weight: 600;
            text-decoration: none;
        }

        .registration-back-link:hover,
        .registration-back-link:focus {
            color: #0d47a1;
            text-decoration: none;
        }

        .registration-grid {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 18px;
        }

        .registration-grid .full-width {
            grid-column: 1 / -1;
        }

        .registration-body label {
            display: block;
            margin-bottom: 8px;
            font-size: 13px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.04em;
            color: #475569;
        }

        .registration-body .form-control {
            height: 48px;
            border-radius: 14px;
            border: 1px solid #cbd5e1;
            box-shadow: none;
            font-size: 15px;
            padding: 12px 14px;
        }

        .registration-body select.form-control {
            padding-right: 36px;
        }

        .registration-submit {
            margin-top: 26px;
            width: 100%;
            min-height: 52px;
            border: 0;
            border-radius: 14px;
            font-size: 16px;
            font-weight: 700;
            background: linear-gradient(135deg, #1d84e8 0%, #1565c0 100%);
            box-shadow: 0 16px 34px rgba(21, 101, 192, 0.28);
        }

        .registration-submit:hover,
        .registration-submit:focus {
            background: linear-gradient(135deg, #1877d4 0%, #0f5cab 100%);
        }

        @media (max-width: 767px) {
            .registration-sidebar,
            .registration-body {
                padding: 28px 22px;
            }

            .registration-body h2 {
                font-size: 26px;
            }

            .registration-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <section class="registration-shell">
        <div class="registration-card">
            <div class="row" style="margin:0;">
                <div class="col-md-5 registration-sidebar">
                    <img src="assets/images/opensis_logo.png" alt="openSIS">
                    <h1>Student Registration</h1>
                    <p>Submit a new student registration request for administrative review. Access is created in a disabled state and only becomes available after school administration verifies the request.</p>
                    <div class="registration-note">
                        Use an email address you can access. School administration will review the request and contact you once the account is verified.
                    </div>
                </div>
                <div class="col-md-7 registration-body">
                    <div class="registration-actions">
                        <a class="registration-back-link" href="index.php?language=<?php echo htmlspecialchars($langCode2, ENT_QUOTES, 'UTF-8'); ?>">
                            <span class="icon-arrow-left12"></span> Back to welcome page
                        </a>
                    </div>

                    <h2>New student registration</h2>
                    <p class="lead-copy">Complete the request below. Once approved, the account can be activated by school administration and used to access the portal.</p>

                    <?php if (!empty($errors)) { ?>
                        <div class="alert alert-danger" role="alert">
                            <ul style="margin: 0; padding-left: 18px;">
                                <?php foreach ($errors as $error_message) { ?>
                                    <li><?php echo htmlspecialchars($error_message, ENT_QUOTES, 'UTF-8'); ?></li>
                                <?php } ?>
                            </ul>
                        </div>
                    <?php } ?>

                    <form method="post" action="PublicCreateAccount.php?language=<?php echo htmlspecialchars($langCode2, ENT_QUOTES, 'UTF-8'); ?>">
                        <input type="hidden" name="registration_token" value="<?php echo htmlspecialchars($_SESSION['public_registration_token'], ENT_QUOTES, 'UTF-8'); ?>">

                        <div class="registration-grid">
                            <div class="full-width">
                                <label for="school_id">School</label>
                                <select class="form-control" id="school_id" name="school_id" required>
                                    <option value="">Select a school</option>
                                    <?php foreach ($schools as $school) { ?>
                                        <option value="<?php echo (int) $school['ID']; ?>" <?php echo (string) $selected_school_id === (string) $school['ID'] ? 'selected' : ''; ?>>
                                            <?php echo htmlspecialchars($school['TITLE'], ENT_QUOTES, 'UTF-8'); ?>
                                        </option>
                                    <?php } ?>
                                </select>
                            </div>

                            <div>
                                <label for="first_name">First name</label>
                                <input class="form-control" id="first_name" name="first_name" type="text" value="<?php echo public_registration_value('first_name'); ?>" required>
                            </div>

                            <div>
                                <label for="last_name">Last name</label>
                                <input class="form-control" id="last_name" name="last_name" type="text" value="<?php echo public_registration_value('last_name'); ?>" required>
                            </div>

                            <div class="full-width">
                                <label for="email">Email address</label>
                                <input class="form-control" id="email" name="email" type="email" value="<?php echo public_registration_value('email'); ?>" required>
                            </div>

                            <div>
                                <label for="username">Username</label>
                                <input class="form-control" id="username" name="username" type="text" value="<?php echo public_registration_value('username'); ?>" required>
                            </div>

                            <div>
                                <label for="password">Password</label>
                                <input class="form-control" id="password" name="password" type="password" required>
                            </div>

                            <div class="full-width">
                                <label for="confirm_password">Confirm password</label>
                                <input class="form-control" id="confirm_password" name="confirm_password" type="password" required>
                            </div>
                        </div>

                        <button class="btn btn-primary registration-submit" type="submit" name="register_submit" value="1">Submit registration request</button>
                    </form>
                </div>
            </div>
        </div>
    </section>
</body>
</html>
