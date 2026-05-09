<?php
# OpenSIS landing page for student access
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

$extra_header  = '';
$extra_header .= '<meta http-equiv="Content-type" content="text/html;charset=UTF-8">';
$extra_header .= '<link href="assets/css/icons/icomoon/styles.css" rel="stylesheet" type="text/css">';
$extra_header .= '<link rel="stylesheet" type="text/css" href="assets/css/bootstrap.min.css">';
$extra_header .= '<link rel="stylesheet" type="text/css" href="assets/css/login.css">';
$extra_header .= '<link href="assets/css/extras/css-checkbox-switch.css" rel="stylesheet">';
Warehouse('header', $extra_header);
?>

<BODY onLoad="document.getElementById('loginLink').focus();">
    <section class="login">
        <div class="login-wrapper">
            <div class="panel">
                <div class="panel-heading">
                    <div class="logo">
                        <img src="assets/images/opensis_logo.png" alt="openSIS" />
                    </div>
                    <h3><?= _studentInformationSystem ?></h3>
                </div>
                <div class="panel-body">
                    <div class="row">
                        <div class="col-md-12 text-center">
                            <h2>Welcome to openSIS</h2>
                            <p class="text-muted">Access the student portal or register for a new student account.</p>
                        </div>
                    </div>
                    <div class="row" style="margin-top: 30px;">
                        <div class="col-md-6">
                            <a id="loginLink" href="index.php?view=login&language=<?= $langCode2 ?>" class="btn btn-primary btn-lg btn-block">Already a student? Login.</a>
                        </div>
                        <div class="col-md-6">
                            <a href="index.php?modfunc=create_account&language=<?= $langCode2 ?>" class="btn btn-success btn-lg btn-block">New Student? Register.</a>
                        </div>
                    </div>
                </div>
                <footer style="margin-top: 20px; text-align: center;">
                    <?= _footerText ?>
                </footer>
            </div>
        </div>
    </section>

    <script src="assets/js/core/libraries/jquery.min.js"></script>
    <script type="text/javascript" src="assets/js/plugins/forms/selects/select2.min.js"></script>
    <script type="text/javascript">
        var language = document.getElementById('language');
        if (language) {
            language.onchange = function() {
                window.location = 'index.php?language=' + this.value;
            };
        }
    </script>
</body>
