# --
# Запуск скриптов по сервисам (для начальной заметки, список доступных
# для сервисов скриптов указывается в настройке Services##AllowedScrpits,
# затем нужные скрипты привязываются в сервисной админке к нужному сервису)
#
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::Event::CheckAndRunAllowedScriptsForArticleCreate;

use strict;
use warnings;
no warnings 'redefine'; ## no critic
use utf8;
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
    'Kernel::System::Service',
);

sub new {

    my ( $Type, %Param ) = @_;

    my $Self = {};

    bless( $Self, $Type );

    return $Self;

}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Event = $Param{Event};
    if ( $Event =~ /ArticleCreate/ ) {
        my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
        my $ScriptsConfig = $ConfigObject->Get('Services');

        if (
            ( IsHashRefWithData( $ScriptsConfig->{AllowedScripts} ) )
            && (
                $Param{Data}->{NewData}->{ArticleType} eq 'InitialNote'
                || $Param{Data}->{NewData}->{ArticleType} eq 'WorkflowInitialNote'
            )
            )
        {
            my $ServiceID = $Param{Data}->{NewData}->{ServiceID}
                ? $Param{Data}->{NewData}->{ServiceID}
                : $Param{Data}{OldTicketData}{ServiceID};
            my %ServicePrefs = $Kernel::OM->Get('Kernel::System::Service')->ServicePreferencesGet(
                ServiceID => $ServiceID,
            );

            #Проверяем актуалность скрипта
            my @PreferenceScripts = split( ', ', $ServicePrefs{AllowedScripts} );
            if ( IsArrayRefWithData( \@PreferenceScripts ) ) {
                for my $Script (@PreferenceScripts) {
                    my %ConfigScripts = reverse %{ $ScriptsConfig->{AllowedScripts} };
                    if ( $ConfigScripts{$Script} ) {
                        $Kernel::OM->Get($Script)->Run(%Param);
                    }
                }
            }
        }
    }
    return 1;
}

1;
