# --
# Заполнение дин. поля CRM URL ссылками по шаблонам соответствующего дин. поля,
# Шаблон дополняется именами и доменами клиентов, которые соответственно берем
# парсингом из начальной заметки
#
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::Event::CRMURLForVKWorkspace;

use strict;
use warnings;
no warnings 'redefine'; ## no critic
use utf8;
use Kernel::System::VariableCheck qw(:all);
use Kernel::System::EmailParser;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
    'Kernel::System::Service',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Email::ValidateEmailAddress',
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
        my $ArticleBody        = $Param{Data}{NewData}{Body};
        my $DynamicFieldConfig = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
            Name => 'CRMURL',
        );

        my @MailAddresess;
        my %HrefsData;
        my (@Emails) = $ArticleBody
            =~ /([a-zA-ZА-Яа-я0-9!#$%&'*+=?^_`|}~-]+(?:\.[a-zA-ZА-Яа-я0-9!#$%&'*+\/=?^_`{|}~-]+)*@((?:[A-Za-zА-Яа-я0-9](?:[A-Za-zА-Яа-я0-9-]*[A-Za-zА-Яа-я0-9])?\.)+[A-Za-zА-Яа-я0-9](?:[A-Za-zА-Яа-я0-9-]*[A-Za-zА-Яа-я])?)|(((?!\-))(xn\-\-)?[a-z0-9\-_]{0,61}[a-z0-9]{1,1}\.)*(xn\-\-)?([a-z0-9\-]{1,61}|[a-z0-9\-]{1,30}))/gm;
        my %UniqueEmails;
        for my $Email (@Emails) {
            if ( ($Email) && ( !$UniqueEmails{ lc($Email) }++ ) ) {
                my $ValidEmail = $Kernel::OM->Get('Kernel::System::Email::ValidateEmailAddress')->Validate(
                    Address       => $Email,
                    CheckIDNEmail => 1,
                );
                if ($ValidEmail) {
                    push( @MailAddresess, $ValidEmail );
                    ( $HrefsData{$ValidEmail}{Name}, $HrefsData{$ValidEmail}{Domain} )
                        = ( $ValidEmail =~ /(.*)@([^@]*)$/ );
                }
            }
        }

        my @DynamicFieldValue;
        if ( IsHashRefWithData( \%HrefsData ) ) {
            for my $EmailAddr ( keys %HrefsData ) {
                my $NameDomainPair = {
                    name   => $HrefsData{$EmailAddr}{Name},
                    domain => $HrefsData{$EmailAddr}{Domain},
                };
                push( @DynamicFieldValue, $NameDomainPair );
            }

            my $Success = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->ValueSet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ObjectID           => $Param{Data}{NewData}{TicketID},
                Value              => \@DynamicFieldValue,
                UserID             => $Param{Data}{NewData}{UserID},
            );
            if ( !$Success ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    'Priority' => 'error',
                    'Message' =>
                        "Can't set CRM URL value for TicketID $Param{Data}{NewData}{TicketID}.",
                );
            }

        }
    }

    return 1;
}

1;
