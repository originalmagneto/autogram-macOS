package digital.slovensko.autogram.core.errors;

public class NoValidKeysDetectedException extends AutogramException {
    public NoValidKeysDetectedException() {
        super("Nastala chyba", "Nenašli sa žiadne platné podpisové certifikáty", "V úložisku certifikátov sa pravdepodobne nenachádzajú žiadne platné podpisové certifikáty, ktoré by sa dali použiť na podpisovanie. Boli však nájdené exspirované certifikáty, ktorými je možné podpisovať až po zmene v nastaveniach.\n\nV prípade nového občianskeho preukazu to môže znamenať, že si potrebujete certifikáty na podpisovanie cez občiansky preukaz vydať. Robí sa to pomocou obslužného softvéru eID klient.", null);
    }
}
