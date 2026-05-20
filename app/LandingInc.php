<?php
error_reporting(0);

include 'lang/supportedLanguages.php';

if (isset($_REQUEST['language']) && in_array($_REQUEST['language'], array_keys($supportedLanguages))) {
    $langCode2 = $_REQUEST['language'];
} elseif (isset($_COOKIE['remember_me_lang']) && in_array($_COOKIE['remember_me_lang'], array_keys($supportedLanguages))) {
    $langCode2 = $_COOKIE['remember_me_lang'];
} else {
    $langCode2 = 'en';
}

$_SESSION['language'] = $langCode2;
include "lang/lang_" . $_SESSION['language'] . ".php";

$is_https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https')
    || (isset($_SERVER['SERVER_PORT']) && (string) $_SERVER['SERVER_PORT'] === '443');
$scheme = $is_https ? 'https' : 'http';
$host = !empty($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : 'opensis.eseosadevbox.com';
$request_uri = !empty($_SERVER['REQUEST_URI']) ? strtok($_SERVER['REQUEST_URI'], '?') : '/';
$canonical_url = $scheme . '://' . $host . rtrim($request_uri ?: '/', '/');
if ($canonical_url === $scheme . '://' . $host) {
    $canonical_url .= '/';
}
$share_image_url = $scheme . '://' . $host . '/assets/images/opensis_logo.png';
$share_title = 'openSIS Student Information System';
$share_description = 'Student information system with student login, registration intake, and school administration workflow under one managed portal.';

$registration_notice = '';
if (!empty($_SESSION['public_registration_notice'])) {
    $registration_notice = $_SESSION['public_registration_notice'];
    unset($_SESSION['public_registration_notice']);
}

$extra_header  = '';
$extra_header .= '<meta http-equiv="Content-type" content="text/html;charset=UTF-8">';
$extra_header .= '<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">';
$extra_header .= '<title>' . htmlspecialchars($share_title, ENT_QUOTES, 'UTF-8') . '</title>';
$extra_header .= '<meta name="description" content="' . htmlspecialchars($share_description, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<meta name="robots" content="index,follow">';
$extra_header .= '<link rel="canonical" href="' . htmlspecialchars($canonical_url, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<meta property="og:type" content="website">';
$extra_header .= '<meta property="og:site_name" content="openSIS">';
$extra_header .= '<meta property="og:title" content="' . htmlspecialchars($share_title, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<meta property="og:description" content="' . htmlspecialchars($share_description, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<meta property="og:url" content="' . htmlspecialchars($canonical_url, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<meta property="og:image" content="' . htmlspecialchars($share_image_url, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<meta property="og:image:alt" content="openSIS logo">';
$extra_header .= '<meta name="twitter:card" content="summary_large_image">';
$extra_header .= '<meta name="twitter:title" content="' . htmlspecialchars($share_title, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<meta name="twitter:description" content="' . htmlspecialchars($share_description, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<meta name="twitter:image" content="' . htmlspecialchars($share_image_url, ENT_QUOTES, 'UTF-8') . '">';
$extra_header .= '<link rel="shortcut icon" href="favicon.ico">';
$extra_header .= '<noscript><meta http-equiv="refresh" content="0;url=EnableJavascript.php" /></noscript>';
$extra_header .= '<link href="assets/css/icons/icomoon/styles.css" rel="stylesheet" type="text/css">';
$extra_header .= '<link rel="stylesheet" type="text/css" href="assets/css/bootstrap.min.css">';
$extra_header .= '<link rel="stylesheet" type="text/css" href="assets/css/login.css">';
$extra_header .= '<link href="assets/css/extras/css-checkbox-switch.css" rel="stylesheet">';
$extra_header .= '<style type="text/css">
    .public-entry-shell {
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 40px 16px;
        background:
            radial-gradient(circle at top, rgba(94, 234, 212, 0.28), rgba(94, 234, 212, 0) 34%),
            linear-gradient(135deg, #0f4c81 0%, #2f80c2 48%, #8aa1b1 100%);
    }

    .public-entry-card {
        width: 100%;
        max-width: 880px;
        background: rgba(255, 255, 255, 0.96);
        border-radius: 24px;
        box-shadow: 0 24px 70px rgba(15, 23, 42, 0.24);
        overflow: hidden;
    }

    .public-entry-brand {
        padding: 36px 40px 28px;
        background: linear-gradient(160deg, rgba(15, 76, 129, 0.96) 0%, rgba(41, 128, 185, 0.92) 100%);
        color: #fff;
        text-align: center;
    }

    .public-entry-brand img {
        max-width: 170px;
        margin-bottom: 18px;
    }

    .public-entry-brand h1 {
        margin: 0 0 10px;
        font-size: 32px;
        font-weight: 700;
        letter-spacing: -0.02em;
    }

    .public-entry-brand p {
        margin: 0 auto;
        max-width: 560px;
        font-size: 16px;
        line-height: 1.6;
        color: rgba(255, 255, 255, 0.88);
    }

    .public-entry-body {
        padding: 36px 40px 40px;
    }

    .public-entry-status {
        margin-bottom: 24px;
    }

    .entry-actions {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 18px;
        margin-top: 28px;
    }

    .entry-action-card {
        display: flex;
        flex-direction: column;
        justify-content: center;
        min-height: 124px;
        padding: 22px 24px;
        border-radius: 18px;
        text-decoration: none;
        transition: transform 0.18s ease, box-shadow 0.18s ease, opacity 0.18s ease;
        box-shadow: 0 16px 34px rgba(15, 23, 42, 0.12);
    }

    .entry-action-card:hover,
    .entry-action-card:focus {
        text-decoration: none;
        transform: translateY(-2px);
        box-shadow: 0 20px 40px rgba(15, 23, 42, 0.16);
        opacity: 0.98;
    }

    .entry-action-card:focus {
        outline: 3px solid rgba(59, 130, 246, 0.24);
        outline-offset: 3px;
    }

    .entry-action-card.primary {
        background: linear-gradient(135deg, #1d84e8 0%, #1565c0 100%);
        color: #ffffff;
    }

    .entry-action-card.success {
        background: linear-gradient(135deg, #4caf50 0%, #2e7d32 100%);
        color: #ffffff;
    }

    .entry-action-eyebrow {
        display: block;
        margin-bottom: 8px;
        font-size: 14px;
        font-weight: 600;
        letter-spacing: 0.02em;
        opacity: 0.92;
    }

    .entry-action-title {
        display: block;
        font-size: 24px;
        font-weight: 700;
        line-height: 1.2;
    }

    .entry-action-copy {
        display: block;
        margin-top: 10px;
        font-size: 14px;
        line-height: 1.5;
        opacity: 0.92;
    }

    .public-entry-footer {
        margin-top: 28px;
        text-align: center;
        color: #64748b;
        font-size: 13px;
        line-height: 1.6;
    }

    @media (max-width: 767px) {
        .public-entry-brand,
        .public-entry-body {
            padding: 28px 22px;
        }

        .public-entry-brand h1 {
            font-size: 28px;
        }

        .entry-actions {
            grid-template-columns: 1fr;
        }

        .entry-action-card {
            min-height: 112px;
            padding: 20px;
        }

        .entry-action-title {
            font-size: 22px;
        }
    }
</style>';

echo '<!DOCTYPE html><html lang="en" dir="' . ((langDirection() == 'rtl') ? 'rtl' : 'ltr') . '"><head>';
echo '<meta charset="utf-8">';
echo $extra_header;
echo '</head>';
?>
<body>
    <section class="public-entry-shell">
        <div class="public-entry-card">
            <div class="public-entry-brand">
                <img src="assets/images/opensis_logo.png" alt="openSIS" />
                <h1>Welcome to openSIS</h1>
                <p>Access the student portal or start a new registration request. New registrations remain pending until school administration reviews and activates the account.</p>
            </div>

            <div class="public-entry-body">
                <?php if (!empty($registration_notice)) { ?>
                    <div class="alert alert-success public-entry-status" role="alert">
                        <?php echo $registration_notice; ?>
                    </div>
                <?php } ?>

                <div class="entry-actions">
                    <a id="loginLink" href="index.php?view=login&language=<?php echo htmlspecialchars($langCode2, ENT_QUOTES, 'UTF-8'); ?>" class="entry-action-card primary">
                        <span class="entry-action-eyebrow">Already a student?</span>
                        <span class="entry-action-title">Login</span>
                        <span class="entry-action-copy">Use your approved portal credentials to continue to the student experience.</span>
                    </a>

                    <a href="PublicCreateAccount.php?language=<?php echo htmlspecialchars($langCode2, ENT_QUOTES, 'UTF-8'); ?>" class="entry-action-card success">
                        <span class="entry-action-eyebrow">New student?</span>
                        <span class="entry-action-title">Register</span>
                        <span class="entry-action-copy">Submit a registration request for administrative review and account activation.</span>
                    </a>
                </div>

                <div class="public-entry-footer">
                    <?php echo _footerText; ?>
                </div>
            </div>
        </div>
    </section>

    <script src="assets/js/core/libraries/jquery.min.js"></script>
    <script type="text/javascript" src="assets/js/plugins/forms/selects/select2.min.js"></script>
</body>
</html>
