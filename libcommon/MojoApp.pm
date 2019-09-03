package libcommon::MojoApp;
use Mojolicious::Lite;
use Data::Dumper qw/Dumper/;
use Mojolicious::Plugin::Sentry;
use Sentry::Raven;
use Mojo::Exception;
use libcommon::log;
use libcommon::config;
libcommon::log->init();
# Mojolicious::Lite
sub sendErrorMessage
{
    $raven->capture_message(shift);
}

sub addDefinitionFile
{
    my $file = shift;
    eval {
        require $file;
    1;
    }
}

sub addTemplatePath
{
    push @{app->renderer->paths}, shift;
}
sub addConfFile
{
    $libcommon::MojoApp::configMojo = libcommon::config::load(@_);
}

sub mojoLogInit
{
    $libcommon::MojoApp::log = libcommon::log::mojoLog(shift);
    return $libcommon::MojoApp::log;
}
sub startApp
{   
    my $class = shift;
    libcommon::log->confLoad($libcommon::MojoApp::configMojo) if $libcommon::MojoApp::configMojo;

    $libcommon::MojoApp::config = $libcommon::MojoApp::configMojo;
    $libcommon::MojoApp::configMojo = $libcommon::MojoApp::configMojo->getSection("MOJOLICIOUS");

    $libcommon::MojoApp::log = mojoLogInit(shift);
    my $chaine = sprintf("%s://%s:%s",$libcommon::MojoApp::configMojo->getKey("protocol"),$libcommon::MojoApp::configMojo->getKey("hostname"),$libcommon::MojoApp::configMojo->getKey("port"));

    app->start('prefork','-l',$chaine);
}
1;
