#!/usr/bin/perl
BEGIN {
    use Linux::Systemd::Daemon ':all';
}

use REST::Client;
use Time::HiRes qw/usleep/;
use sigtrap qw /handler handleSignal normal-signals/;
use strict;
use warnings;
use JSON::XS;
use Data::Dumper qw/Dumper/;
use libcommon::log;
use libcommon::config;
use IO::Socket::INET;
use Storable qw/fd_retrieve/;
use IO::Select;
use utf8;
use threads;
use threads::shared;
use POSIX 'strftime';

libcommon::log->init();
my $Config = libcommon::config::load("/PERL/Etna/login.ini");
libcommon::log->confLoad($Config);



my @result = ("Le projet est en bonne voie", "Le projet est en bonne voie malgré quelque problème rencontré", "Malgré les problèmes rencontré le projet est en bonne voie", "le projet avance bien", "Le projet est ralentie car necessite des connaisances");


my $configL = $Config->getSection("GENERAL");
my $configModule = $Config->getSection("MODULE");
my $configHeureM = $Config->getSection("HEUREM");
my $configHeureA = $Config->getSection("HEUREM");



my $data = {"login" => $configL->getKey("login"),"password"=> $configL->getKey("password")};
$data = JSON::XS->new->utf8->encode($data);

my $browser = uaRefresh();

my $port_listen = 2808;


my ($sec, $min, $hour, $mday, $mon, $year, $wday) = localtime(time());
$year = $year + 1900;
$mon = $mon + 1;
my $start =sprintf("%s-%02s-%02s %s:%s", $year,$mon,$mday, $configHeureM->getKey("start"), "00");
my $stop =sprintf("%s-%02s-%02s %s:%s", $year,$mon,$mday, $configHeureM->getKey("stop"), "00");

print $start,"\n";
print $stop,"\n";
$| = 1; # Autoflush

my $msg :shared;
print "Création de la socket\n";
my $socket = IO::Socket::INET->new(

    LocalHost   => '0.0.0.0',
    LocalPort   =>  $port_listen,
    Proto       => 'tcp',
    Listen      =>  5,
    Reuse       =>  1,
    Blocking => 0

) or die "Cannot create socket";

 #my $select = new IO::Select();
#$select->add($socket);


my $continue = 1;

my $module :shared;
print "Création du thread\n";
my $thr2 = threads->create(\&socketR);
my $time = time();
my $todayW =0;
sub socketR
{
    while($continue)
    {
        while( my $s = $socket->accept) {
            my $val = Storable::fd_retrieve($s);    
            my $dec = generateMSG($val); 
            $msg = $dec;
            share($msg);
            $module = $val->{module};
            share($module);
        }
        usleep 100;
    }
}

sd_notify(READY => 1);

my $obj;
my $decl = 0;
print "Juste avant la boucle\n";
while ($continue) {
    sd_notify(WATCHDOG => 1);
    if ((time() - $time) > 86400)
    {
       print "Je demande mes coockies\n";
       $browser = uaRefresh();
       $time = time();
    }
    if ($msg && !$obj)
    {    
        print "J'ai recu un message\n";
        $obj = $msg;
        $msg = undef;
    }
    ($sec, $min, $hour, $mday, $mon, $year, $wday) = localtime();
    if ($hour == $configHeureM->getKey("start"))
    {
        $decl = 0;
    }
    if ($hour >= $configHeureM->getKey("stop") && $obj)
    {
        print "Création d'une déclaration\n";
        $browser->POST("https://intra-api.etna-alternance.net/modules/$module/declareLogs", $obj);
        
        $obj = undef;
        $decl = 1;
    }
    #print $hour,"\n";
    #print $configHeureM->getKey("stop"),"\n";
    if ($hour >= $configHeureM->getKey("stop") && $decl != 1 )
    {
        
        libcommon::log::printf("notice","Création d'une fake déclaration\n");
        my $module = $configModule->getKey("DEFAULT");
        my $content = generateFake();
        my $dec = {module => $module, declaration=>{start=> $start, end=> $stop, content=> $content}};
        $dec = JSON::XS->new->utf8->encode($dec);
        $browser->POST("https://intra-api.etna-alternance.net/modules/$module/declareLogs", $dec);
        $decl = 1;
    }
    usleep 10000;
}
$thr2->join;

sub uaRefresh
{
    my $ua = LWP::UserAgent->new(cookie_jar => {});
    my $browser = REST::Client->new(useragent => $ua);
    $browser->addHeader("Content-Type","application/json;charset=UTF-8");
    $browser->POST("https://auth.etna-alternance.net/login",$data);
    return $browser;
}

###############################################################################
# reloading or stopping daemon on unix signals SIGHUP and SIGTERM (respect.)
###############################################################################
sub handleSignal {   
    my $signal = shift;
    print $signal,"\n";
    #################################################
    # SIGTERM or SIGINT : prevent next loop to start
    #################################################
    if ($signal eq "TERM" or $signal eq "INT") {
        $continue = 0;
        threads->exit();
        close($socket);
    }
    return 1;
}

sub generateMSG
{
    my $val = shift;
    my $action = "";
    foreach  my $a (keys %{$val->{action}})
    {
        foreach  my $act (@{$val->{action}->{$a}})
        {
            if ($a =~ "ajout")
            {
                if ($act =~ /\.xml/)
                {
                    $action .= "\t - Ajout d'un fichier de description au format xml $act";
                }
                elsif ($act =~ /\.dll/)
                {
                    $action .= "\t - Ajout d'une bibliothèque $act";
                }
                elsif ($act =~ /\.pl/)
                {
                    $action .= "\t - Ajout d'un fichier perl (Code) $act";
                }
                elsif ($act =~ /\.c/)
                {
                    $action .= "\t - ajout d'un fichier c (code) $act";
                }
                elsif ($act =~ /\.xaml/)
                {
                    $action .= "\t - Ajout d'un fichier de description au format xaml $act";
                }
                elsif ($act =~ /\.xaml\.cs/)
                {
                    $action .= "\t - Ajout d'un fichier c# code behind (Code) $act";
                }
                elsif ($act =~ /\.cs/)
                {
                    $action .= "\t - Ajout d'un fichier c# (Code) $act";
                }
                else
                {
                    $action .= "\t - Ajout du fichier : $act\n";
                }
            }
            elsif ($a =~ "sup")
            {
                $action .= "\t - Suppression du fichier : $act\n";
            }
            elsif ($a =~  "mod")
            {
                $action .= "\t - Modification du fichier : $act\n";
            }
            elsif ($a =~ "rename")
            {
                $action .= "\t - Changement de nom pour le fichier : $act\n";
            }
        }
    }
    my $rand = int(rand(5));
    my $module = $configModule->getKey($val->{Repertoire});
    my $resultat = $result[$rand];
    my $dec = {module => $module, declaration=>{start=> $start, end=> $stop, content=> "- Objectifs: $val->{commitMessage}\n - Actions: \n$action\n- Résultats: $resultat"}};
    $dec = JSON::XS->new->utf8->encode($dec);
    return $dec;
}

sub generateFake
{
    my @content = ("- Objectifs: Avancer sur le projet\n - Actions: Lecture de documentation afin de pouvoir répondre au besoin technique du projet\n- Résultats: J'ai une vision plus précise des besoins du projets et des possibilité des technos","- Objectifs: Partager les connaisances entre les membres du groupe\n - Actions: Réunion d'équipe afin d'indentifier les lacunes parmis les membres du groupe\n- Résultats: Certain problème on été identifié et corrigé cependant il reste encore des lacunes","- Objectifs: Avancer sur le projet\n - Actions: Mise en place de l'environnement tecnique adapté afin d'avancé suivi de la lecture de documentation pour la techno\n- Résultats: lancement de code et apprentisage de la techno","- Objectifs: faire une réunion d'équipe\n - Actions: Répartition du travail en fonction des taches à réaliser et des compétences de chancun.\n- Résultats: répartition des taches a court terme jusqu'a la prochaine réunion","- Objectifs: Regarder les taches restantes sur le projet\n - Actions: Réunion d'équipe, lecture du sujet , vérification de l'éxistant\n- Résultats: répartition des taches à court terme");
    my $rand = int(rand(5));
    return $content[$rand];
}
