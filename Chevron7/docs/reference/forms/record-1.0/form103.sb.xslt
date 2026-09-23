<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:egonp="https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0">
  <xsl:output method="text" indent="yes" omit-xml-declaration="yes" encoding="UTF-8"/>
  <xsl:strip-space elements="*"/>

  <xsl:template match="/">
    <xsl:text>Záznam o zaručenej konverzii z listinej podoby do elektronického dokumentu</xsl:text>
    <xsl:for-each select="egonp:ConversionRecord">
      <xsl:text>&#xa;</xsl:text>

      <xsl:text>&#xa;Údaje o pôvodných listinných dokumentoch: </xsl:text>
      <xsl:apply-templates select="egonp:OriginalDocumentInfo"></xsl:apply-templates>

      <xsl:text>&#xa;</xsl:text>
      <xsl:text>&#xa;Údaje novovzniknutého dokumentu v elektronickej forme: </xsl:text>
      <xsl:apply-templates select="egonp:NewDocumentInfo"></xsl:apply-templates>

      <xsl:text>&#xa;</xsl:text>
      <xsl:text>&#xa;Údaje o zaručenej konverzii: </xsl:text>
      <xsl:apply-templates select="egonp:ConversionRecordEvidenceNumber"></xsl:apply-templates>
      <xsl:apply-templates select="egonp:ConversionExecutionDateTime"></xsl:apply-templates>
      <xsl:apply-templates select="egonp:UsedDevice"></xsl:apply-templates>

      <xsl:text>&#xa;</xsl:text>
      <xsl:text>&#xa;Zaručenú konverziu vykonal: </xsl:text>
      <xsl:apply-templates select="egonp:PersonPerformingConversion"></xsl:apply-templates>

    </xsl:for-each>
  </xsl:template>

  <xsl:template match="egonp:ConversionRecord">
    <xsl:text>&#xa;</xsl:text>Záznam č. <xsl:value-of select="position()"></xsl:value-of><xsl:text>&#xa;</xsl:text>
  </xsl:template>

  <xsl:template match="egonp:OriginalDocumentsQuantity">
    Formát pôvodného dokumentu: <xsl:value-of select="@Format"></xsl:value-of>, Počet dokumentov: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:ExecutedConversionTypesQuantity[@ConversionType = 2]">
    Počet konverzií z listinnej formy do elektronickej formy: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <!-- ORIGINAL DOKUMENT -->
  <xsl:template match="egonp:OriginalDocumentInfo">
    <xsl:text>&#xa;</xsl:text>
    <xsl:text>&#xa;</xsl:text> Pôvodný listinný dokument č. <xsl:value-of select="position()"></xsl:value-of>
    <xsl:apply-templates select="egonp:OriginalDocumentName"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:OriginalDocumentOrder"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:OriginalDocumentType"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:OriginalDocumentNumberOfSheets"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:OriginalDocumentNonEmptyPageCount"></xsl:apply-templates>
    
    <xsl:text>&#xa;</xsl:text>
    <xsl:text>&#xa;  Formát papiera pôvodného dokumentu</xsl:text>
    <xsl:apply-templates select="egonp:OriginalDocumentPaperSize"></xsl:apply-templates>
    
    <xsl:text>&#xa;</xsl:text>
    <xsl:text>&#xa;  Bezpečnostné prvky originálneho dokumentu</xsl:text>
    <xsl:apply-templates select="egonp:DocumentSecurityElementsDetails"></xsl:apply-templates>
  </xsl:template>

  <xsl:template match="egonp:OriginalDocumentName">
    Názov pôvodného dokumentu: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:OriginalDocumentOrder">
    Poradie pôvodného dokumentu: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:OriginalDocumentType">
    Typ pôvodného dokumentu: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:OriginalDocumentNumberOfSheets">
    Počet strán pôvodného dokumentu: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:OriginalDocumentNonEmptyPageCount">
    Počet neprázdnych strán pôvodného dokumentu: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:PaperSize">
    Formát papiera: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:PaperSizeNumberOfSheets">
    Počet listov: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:OriginalDocumentPaperSize">
    <xsl:text>&#xa;</xsl:text>
    <xsl:text>&#xa;   Formát papiera:</xsl:text>
      <xsl:apply-templates select="egonp:PaperSize"></xsl:apply-templates>
      <xsl:apply-templates select="egonp:PaperSizeNumberOfSheets"></xsl:apply-templates>
  </xsl:template>

  <xsl:template match="egonp:DocumentSecurityElementsDetails">
    <xsl:text>&#xa;</xsl:text>
    <xsl:text>&#xa;   Bezpečnostný prvok:</xsl:text>
      <xsl:apply-templates select="egonp:OriginalDocumentSecurityElementsDescription"></xsl:apply-templates>
      <xsl:apply-templates select="egonp:OriginalDocumentSecurityElementsPage"></xsl:apply-templates>
      <xsl:apply-templates select="egonp:OriginalDocumentSecurityElementsSheet"></xsl:apply-templates>
      <xsl:apply-templates select="egonp:OriginalDocumentSecurityElementsLocation"></xsl:apply-templates>
      <xsl:apply-templates select="egonp:NewDocumentSecurityElementsPage"></xsl:apply-templates>
  </xsl:template>

  <xsl:template match="egonp:OriginalDocumentSecurityElementsDescription">
    Slovný opis: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>
  <xsl:template match="egonp:OriginalDocumentSecurityElementsPage">
    Výskyt na strane: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>
  <xsl:template match="egonp:OriginalDocumentSecurityElementsSheet">
    Výskyt na liste: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>
  <xsl:template match="egonp:OriginalDocumentSecurityElementsLocation">
    Miesto umiestnenia na strane dokumentu: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>
  <xsl:template match="egonp:NewDocumentSecurityElementsPage">
    Vyskyt na strane v novovzniknutom dokumente v el. podobe: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <!-- NOVY DOKUMENT -->
  <xsl:template match="egonp:NewDocumentInfo">
    <xsl:apply-templates select="egonp:NewDocumentName"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:NewDocumentFormat"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:ElectronicFingerprintValue"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:ElectronicFingerprintCalculationMethod"></xsl:apply-templates>
  </xsl:template>

  <xsl:template match="egonp:NewDocumentName">
    Názov nového dokumentu: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>
  <xsl:template match="egonp:NewDocumentFormat">
    Formát nového dokumentu: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>
  <xsl:template match="egonp:ElectronicFingerprintValue">
    Hodnota el. odtlačku: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>
  <xsl:template match="egonp:ElectronicFingerprintCalculationMethod">
    Funkcia použitá na výpočet elektronického odtlačku: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:ConversionRecordEvidenceNumber">
    Evidenčné číslo záznamu o konverzii: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:UsedDevice">
    Použité zariadenie: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:ConversionExecutionDateTime">
    Čas vykonania konverzie: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <!-- OSOBA VYKONAVAJUCA KONVERZIU -->
  <xsl:template match="egonp:PersonPerformingConversion">
    <xsl:apply-templates select="egonp:PersonData/egonp:ID/egonp:IdentifierValue"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:PersonData/egonp:LegalSubject/egonp:Name"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:PersonData/egonp:PhysicalPerson/egonp:PersonName/egonp:GivenName"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:PersonData/egonp:PhysicalPerson/egonp:PersonName/egonp:FamilyName"></xsl:apply-templates>
    <xsl:apply-templates select="egonp:PersonData/egonp:PhysicalPerson/egonp:Position"></xsl:apply-templates>
    <xsl:text>&#xa;</xsl:text>
  </xsl:template>

  <xsl:template match="egonp:ID/egonp:IdentifierValue">
    Identifikačné číslo: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:LegalSubject/egonp:Name">
    Názov právnickej osoby: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:GivenName">
    Meno: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:FamilyName">
    Priezvisko: <xsl:value-of select="concat(' ', . , ' ')"></xsl:value-of>
  </xsl:template>

  <xsl:template match="egonp:Position">
    Funkcia alebo pracovné zaradenie: <xsl:value-of select="."></xsl:value-of>
  </xsl:template>

</xsl:stylesheet>