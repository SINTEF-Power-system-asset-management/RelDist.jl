# TODO

- Koble til resten av koden
    - [x] Reimplementere traverse_and_get_sectioning_time()
    - [ ] Reimplementere den gamle sectioning-algoritmen
- [ ] Outputs: U, t, ENS, CENS, r, lambda (mangler CENS)
- [ ] Hva skjer hvis reparasjonstida endrer seg? eller U?
- [ ] Finne splitting time for den gitte løsninga
- [ ] Dokumentere
- [ ] Batteri
- [ ] Slutte å anta at alle kanter har en switch / preprocesse slik at alle kanter får en switch
- [ ] Optimize  
    1. Finn bedre forslag til Parts først:
        - Hvis man bare ser på en enkelt forsyning reduseres kompleksiteten veldig.
        - Deretter kan man trekke fra all overlappen og starte mye nærmere fasit.
        - Hvis alle laster er støttede av den naive fremgangsmåten kan man hoppe over hele det komplekse søket.
    2. Preprosessering av grafen
        - Kombiner alle laster med to eller færre naboer med naboen sin.
        - Kan føre til at laster i grensen blir for store og ikke kan støttes lengre, men da kan man bruke det imperfekte resultatet som startpunkt som beskrevet i forslag 1.
    