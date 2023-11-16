

s1 = Switch("1", "2", 1, Inf)
s2 = Switch("1", "2", 2, Inf)
s3 = Switch("1", "2", 3, 0.1)
s4 = Switch()

@test s1 < s2
@test s3 < s1
@test s4 < s3
