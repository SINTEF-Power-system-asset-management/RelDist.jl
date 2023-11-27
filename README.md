# RelDist.jl
Relrad.jl is an open source tool for estimating the reliability of radially operated distribution grids.

The algorithm used by the tool is based on the RELRAD methodology [1]. For the sake of computer implementation the method was rewritten in terms of graph theory [2]. 

In the CINELDI project further functionality has been added.

## Example 
The example folder contains three examples
* reliability_course
* fasad
* CINELDI

The example in the reliability_course folder is based on an exercise given in a reliability course taught at NTNU. The example in the fasad folder is from a previous project at Sintef Energy Research [3], and inspired by a test network used in [4]. In the folder a censored version of the network used in [2] is included. The censored network differs a bit from the network used in [2] and different results are to be expected. A paper describing the test network is available at [5].


[1]: https://ieeexplore.ieee.org/abstract/document/127084
[2]: https://www.researchgate.net/publication/354477932_An_open-source_tool_for_reliability_analysis_in_radial_distribution_grids
[3]: https://www.sintef.no/prosjekter/2015/feil-og-avbruddshandtering-i-smarte-distribusjonsn/
[4]: http://hdl.handle.net/11250/257113
[5]: https://doi.org/10.1016/j.dib.2023.109025
