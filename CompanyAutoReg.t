# Тест на некоторые методы авторегистрации компаний -
# На создание и заполнение дин. поля типа SubscriptionTemplates
# На создание компании - шаблона, невозможности регистрицаа клиента в такой компании, и на возможность создать подписку для компании такого типа

use strict;
use warnings;
use utf8;
use Encode qw(decode encode);
use Kernel::System::VariableCheck qw(:all);

use vars (qw($Self));

# get needed objects
my $ConfigObject              = $Kernel::OM->Get('Kernel::Config');
my $LinkObject                = $Kernel::OM->Get('Kernel::System::LinkObject');
my $MainObject                = $Kernel::OM->Get('Kernel::System::Main');
my $UserObject                = $Kernel::OM->Get('Kernel::System::User');
my $CustomerCompanyObject     = $Kernel::OM->Get('Kernel::System::CustomerCompany');
my $ServiceObject             = $Kernel::OM->Get('Kernel::System::Service');
my $GeneralCatalogObject      = $Kernel::OM->Get('Kernel::System::GeneralCatalog');
my $ConfigItemObject          = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');
my $CustomerUserObject        = $Kernel::OM->Get('Kernel::System::CustomerUser');
my $MAILObject                = $Kernel::OM->Get('Kernel::System::CustomerCompany::MAIL');
my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
my $DynamicFieldOtrsType      = $DynamicFieldObject->DynamicFieldGet(
    Name => 'OtrsOrganisationType',
);
my $PossibleValues = $DynamicFieldOtrsType->{Config}->{PossibleValues};
$PossibleValues->{'template'} = "Шаблоны" if !$PossibleValues->{'template'};
$DynamicFieldOtrsType->{Config}->{PossibleValues} = $PossibleValues;
$DynamicFieldObject->DynamicFieldUpdate(
    %$DynamicFieldOtrsType,
    Reorder => 0,
    UserID  => 1,
);

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

my $RandomID = $Helper->GetRandomID();
my @TemplateIDs;
my @CompanyEmails;
my @EmailsFrom;
my @CompanyIDs;
my $EAVCustomerUserSourceName =
    $Kernel::OM->Get('Kernel::Config')->Get('EAVCustomerUserSourceName');
my $EAVCustomerCompanySourceName =
    $Kernel::OM->Get('Kernel::Config')->Get('EAVCustomerCompanySourceName');

for my $Counter ( 1 .. 3 ) {
    my $EmailForCompanyRand = 'Email' . $Counter . '@test' . $RandomID . 'ru';
    my $EmailsFrom          = 'From' . $Counter . '@test' . $RandomID . 'ru';
    my $TemplateRand        = 'Template' . $Counter . $RandomID;

    # create new users for the tests
    my $TemplateID = $CustomerCompanyObject->CustomerCompanyAdd(
        CustomerID             => $TemplateRand,
        CustomerCompanyName    => $TemplateRand . ' Inc',
        CustomerCompanyStreet  => 'Some Street',
        CustomerCompanyZIP     => '12345',
        CustomerCompanyCity    => 'Some city',
        CustomerCompanyCountry => 'USA',
        CustomerCompanyURL     => 'http://example.com',
        CustomerCompanyComment => 'some comment',
        Source                 => $EAVCustomerCompanySourceName,
        ValidID                => 1,
        UserID                 => 1,
        OtrsOrganisationType   => 'template',
    );
    $DynamicFieldBackendObject->ValueSet(
        DynamicFieldConfig => $DynamicFieldOtrsType,
        ObjectName         => $TemplateID,
        Value              => 'template',
        UserID             => 1,
    );

    my $CompanyRand = $Counter . $RandomID;

    # create new users for the tests
    my $CustomerID = $CustomerCompanyObject->CustomerCompanyAdd(
        CustomerID             => $CompanyRand,
        CustomerCompanyName    => $CompanyRand . ' Inc',
        CustomerCompanyStreet  => 'Some Street',
        CustomerCompanyZIP     => '12345',
        CustomerCompanyCity    => 'Some city',
        CustomerCompanyCountry => 'USA',
        CustomerCompanyURL     => 'http://example.com',
        CustomerCompanyComment => 'some comment',
        ValidID                => 1,
        UserID                 => 1,
        EmailInbox             => $EmailForCompanyRand,
    );

    push @CompanyIDs, $CustomerID;

    push @TemplateIDs, $TemplateID;

    push @CompanyEmails, $EmailForCompanyRand;

    push @EmailsFrom, $EmailsFrom;
}

my $GeneralCatalogClass = 'ITSM::ConfigItem::Class';

my $GenCatalog = $Kernel::OM->Get('Kernel::System::GeneralCatalog')->ItemGet(
    Class => 'ITSM::ConfigItem::Class',
    Name  => 'Домены',
) || {};

# add a domain item
my $ItemID;
if ( $GenCatalog->{ItemID} ) {
    $ItemID = $GenCatalog->{ItemID};
}
else {
    $ItemID = $GeneralCatalogObject->ItemAdd(
        Class   => $GeneralCatalogClass,
        Name    => "Домены",
        ValidID => 1,
        UserID  => 1,
    );

    # check item id
    if ( !$ItemID ) {

        $Self->True(
            0,
            "Can't add new general catalog item.",
        );
    }
}

my $ConfigItemDefinition = '[
            {
            "CountMin" => "1",
            "Input" => {
                         "Type" => "Text",
                         "Size" => "50",
                         "MaxLength" => "50"
                       },
            "CountMax" => "1",
            "CountDefault" => "1",
            "Name" => "domain",
            "Key" => "domain"
          },
          {
            "CountMin" => "1",
            "Input" => {
                         "Type" => "Text",
                         "Size" => "50",
                         "MaxLength" => "255"
                       },
            "CountMax" => "1",
            "CountDefault" => "1",
            "Name" => "title",
            "Key" => "title"
          },
        ]';

# add a definition to the class
my $DefinitionID = $ConfigItemObject->DefinitionAdd(
    ClassID    => $ItemID,
    Definition => $ConfigItemDefinition,
    UserID     => 1,
);

# check definition id
if ( !$DefinitionID ) {

    $Self->True(
        0,
        "Can't add new config item definition.",
    );
}

# Проверим что нельзя зарегистрировать клиента на компанию-шаблон
foreach my $TemplateID (@TemplateIDs) {
    my $UserRand = $RandomID . $TemplateID;
    my $UserID   = $CustomerUserObject->CustomerUserAdd(
        Source         => $EAVCustomerUserSourceName,
        UserFirstname  => 'Firstname Test',
        UserLastname   => 'Lastname Test',
        UserMiddlename => 'Middlename test',
        UserCustomerID => $TemplateID,
        UserLogin      => $UserRand,
        UserEmail      => $UserRand . '-Email@example.com',
        UserPassword   => 'some_pass',
        ValidID        => 1,
        UserID         => 1,
    );

    $Self->False(
        $UserID,
        "CustomerUserAdd() to template should not be possible - $UserID",
    );
}

# Проверка создания КЕ с нужным доменом
my $VersionID = $MAILObject->DomainConfigItemCreate( Domain => 'TestDomain.ru' );
$Self->True(
    $VersionID,
    "CI with needed domain is not created",
);

# Проверка на наличие КЕ с нашим доменом
$VersionID = $MAILObject->CheckDomain( Domain => 'TestDomain.ru' );
$Self->True(
    $VersionID,
    "CI with needed domain is missing",
);

# Проверяем необходимые дин. поля

my $DynamicFieldConfigInheritedTemplates = $DynamicFieldObject->DynamicFieldGet(
    Name => 'LinkedInheritedTemplates',
);

if ( !IsHashRefWithData($DynamicFieldConfigInheritedTemplates) ) {

    $DynamicFieldConfigInheritedTemplates = {
        Name       => 'LinkedInheritedTemplates',
        Label      => 'LinkedInheritedTemplates',
        FieldType  => 'Text',
        ObjectType => 'CustomerCompany',
        Config     => {
            TranslatableValues => '0',
        },
    };
    my $ID = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldAdd(
        %{$DynamicFieldConfigInheritedTemplates},
        FieldOrder => 99999,
        ValidID    => 1,
        UserID     => 1,
    );
    $Self->True(
        $ID,
        "NewDynamicFieldAdded - linkedinheritedtemplates - $ID",
    );
}

my $DynamicFieldConfigSubscriptionTemplates = $DynamicFieldObject->DynamicFieldGet(
    Name => 'SubscriptionTemplates',
);

if ( !IsHashRefWithData($DynamicFieldConfigSubscriptionTemplates) ) {

    $DynamicFieldConfigSubscriptionTemplates = {
        Name       => 'SubscriptionTemplates',
        Label      => 'SubscriptionTemplates',
        FieldType  => 'SubscriptionTemplates',
        ObjectType => 'CustomerCompany',
        Config     => {
            TranslatableValues => '0',
            PossibleValues     => {
                $TemplateIDs[0] => 'Template1',
                $TemplateIDs[1] => 'Template2',
                $TemplateIDs[2] => 'Template3'
            },
        },

    };
    my $ID = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldAdd(
        %{$DynamicFieldConfigSubscriptionTemplates},
        FieldOrder => 99999,
        ValidID    => 1,
        UserID     => 1,
    );
    $Self->True(
        $ID,
        "NewDynamicFieldAdded - SubscriptionTemplates - $ID",
    );
}
else {

    my $DynamicFieldData = $DynamicFieldObject->DynamicFieldGet(
        Name => 'SubscriptionTemplates',
    );
    my $PossibleValues = $DynamicFieldData->{Config}->{PossibleValues};
    $PossibleValues->{ $TemplateIDs[0] }          = 'Template1';
    $PossibleValues->{ $TemplateIDs[1] }          = 'Template2';
    $PossibleValues->{ $TemplateIDs[2] }          = 'Template3';
    $DynamicFieldData->{Config}->{PossibleValues} = $PossibleValues;
    $DynamicFieldObject->DynamicFieldUpdate(
        %$DynamicFieldData,
        Reorder => 0,
        UserID  => 1,
    );

}
my $DynamicFieldData = $DynamicFieldObject->DynamicFieldGet(
    Name => 'SubscriptionTemplates',
);

$Self->Is(
    $DynamicFieldData->{Config}->{PossibleValues}->{ $TemplateIDs[0] },
    'Template1',
    "SubscriptionTemplates Doesnt contain template 1",
);
$Self->Is(
    $DynamicFieldData->{Config}->{PossibleValues}->{ $TemplateIDs[1] },
    'Template2',
    "SubscriptionTemplates Doesnt contain template 2",
);
$Self->Is(
    $DynamicFieldData->{Config}->{PossibleValues}->{ $TemplateIDs[2] },
    'Template3',
    "SubscriptionTemplates Doesnt contain template 3",
);

# Создаем новый сервис

my $ServiceName = "TestService1";
my $ServiceData = {
    Add => {
        Name    => $ServiceName,
        Code    => $ServiceName,
        ValidID => 1,
        UserID  => 1,

        # ---
        # ITSMCore
        # ---
        TypeID      => 1,
        Criticality => 'normal',

        # ---
    },
    AddGet => {
        ParentID  => '',
        Name      => $ServiceName,
        Code      => $ServiceName,
        NameShort => $ServiceName,
        ValidID   => 1,
        Comment   => '',
        CreateBy  => 1,
        ChangeBy  => 1,

        # ---
        # ITSMCore
        # ---
        TypeID      => 1,
        Criticality => 'normal',

        # ---
    },
};

my $ServiceID = $ServiceObject->ServiceAdd(
    %{ $ServiceData->{Add} },
);
$Self->True(
    $ServiceID,
    "New Service Added $ServiceID",
);

# Назначаем подписку шаблону
my %SubscriptionsData;
my $SubsObj = Kernel::System::EAV->new('Subscription');
$SubscriptionsData{$ServiceID} = {
    'OwnerID'   => $TemplateIDs[0],
    'SLAID'     => 1,
    'ServiceID' => $ServiceID,
    'AddressID' => 0,
    'deny'      => 0,
    'data'      => {
        'subscription' => {
            'type_subscription' => 0
        },
        'publish' => 0,
    }
};
my $Res = $SubsObj->Create( $SubscriptionsData{$ServiceID} );
$Self->True(
    $Res,
    "Didn't create subscription ",
);

if ($Res) {
    my $SubscriptionID = $Res->id();
    $Self->True(
        $SubscriptionID,
        "Didn't create subscription $SubscriptionID",
    );
}
1;
