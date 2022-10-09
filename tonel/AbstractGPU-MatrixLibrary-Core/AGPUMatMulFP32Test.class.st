Class {
	#name : #AGPUMatMulFP32Test,
	#superclass : #TestCase,
	#category : #'AbstractGPU-MatrixLibrary-Core'
}

{ #category : #tests }
AGPUMatMulFP32Test >> test_1x2_2x1 [
	| lhs rhs result |
	lhs := AGPUMatrix rows: 1 columns: 2 tabulate: [ :r :c |
		({{1. 2}.
		  {}} at: r) at: c ].
	
	rhs := AGPUMatrix rows: 2 columns: 1 tabulate: [ :r :c |
		({{10}.
		  {20}} at: r) at: c ].

	result := AGPUMatrix rows: 1 columns: 1 tabulate: [ :r :c |
		({{50.0}.
		  {}} at: r) at: c ].
	result contentsAsFloatArray.
	
	self assert: lhs @! rhs equals: result.
	self assert: lhs @ rhs equals: result.

]

{ #category : #tests }
AGPUMatMulFP32Test >> test_2x2 [
	| lhs rhs result |
	lhs := AGPUMatrix rows: 2 columns: 2 tabulate: [ :r :c |
		({{1. 2}.
		  {3. 4}} at: r) at: c ].
	
	rhs := AGPUMatrix rows: 2 columns: 2 tabulate: [ :r :c |
		({{10. 20}.
		  {30. 40}} at: r) at: c ].

	result := AGPUMatrix rows: 2 columns: 2 tabulate: [ :r :c |
		({{70. 100}.
		  {150. 220}} at: r) at: c ].
	result contentsAsFloatArray.
	
	self assert: lhs @! rhs equals: result.
	self assert: lhs @ rhs equals: result.

]

{ #category : #tests }
AGPUMatMulFP32Test >> test_64x64 [
	| lhs rhs gpuresult gputime cpuresult cputime size gpuRounded cpuRounded |
	size := 64.
	lhs := AGPUMatrix rows: size columns: size tabulate: [ :r :c | r / c ].	
	rhs := lhs copy. 
	
	gputime := [ gpuresult := lhs @ rhs ] timeToRun.
	cputime := [ cpuresult := lhs @! rhs ] timeToRun.

	Transcript crShow: 'CPU time: '; show: cputime; crShow: 'GPU Time: '; show: gputime; cr.
	gpuRounded := 0.
	cpuRounded := 0.
	
	gpuRounded := gpuresult asFloatArray collect: [ :x | x round: 4].
	cpuRounded := cpuresult asFloatArray collect: [ :x | x round: 4].
	
	"At these large numbers the cpu and gpu results deviate by a small bit"
	gpuRounded doWithIndex: [ :el :i | | diff |
		diff := el / (cpuRounded at: i). 
		self assert: diff <= 1.00001 ].
		
]

{ #category : #tests }
AGPUMatMulFP32Test >> test_80x80 [
	| lhs rhs gpuresult gputime cpuresult cputime size gpuRounded cpuRounded |
	size := 80.
	lhs := AGPUMatrix rows: size columns: size tabulate: [ :r :c | r / c ].	
	rhs := lhs copy. 
	
	gputime := [ gpuresult := lhs @ rhs ] timeToRun.
	cputime := [ cpuresult := lhs @! rhs ] timeToRun.

	Transcript crShow: 'CPU time: '; show: cputime; crShow: 'GPU Time: '; show: gputime; cr.

	gpuRounded := gpuresult asFloatArray collect: [ :x | x round: 4].
	cpuRounded := cpuresult asFloatArray collect: [ :x | x round: 4].
	
	"At these large numbers the cpu and gpu results deviate by a small bit"
	gpuRounded doWithIndex: [ :el :i | | diff |
		diff := el / (cpuRounded at: i). 
		self assert: diff <= 1.0001 ].
	
]

{ #category : #tests }
AGPUMatMulFP32Test >> test_99x99 [
	| lhs rhs gpuResult gpuResult2 gpuTime cpuResult cpuResult2 cpuTime size compare x gpuResult2Array |
	size := 99.
	lhs := AGPUMatrix rows: size columns: size tabulate: [ :r :c |  1 / (r * c) asFloat].	
	rhs := lhs copy. 

	gpuTime := [ gpuResult := lhs @ rhs ] timeToRun.
	cpuTime := [ cpuResult := lhs @! rhs ] timeToRun.
	gpuResult2 := lhs @ rhs. 
	cpuResult2 := lhs @! rhs.

	self assert: cpuResult equals: cpuResult2.
	compare := OrderedCollection new.
	gpuResult2Array := gpuResult2 asArray.
	gpuResult asArray withIndexDo: [ :e :i | compare add: { e / (gpuResult2Array at: i). e. (gpuResult2Array at: i) } ].
	self assert: gpuResult equals: gpuResult2.
	

	Transcript crShow: 'CPU time: '; show: cpuTime; crShow: 'GPU Time: '; show: gpuTime; cr.

	compare := cpuResult withIndexCollect: [ :e :i | 
		{ 	(e / (gpuResult at: i)) round: 4 . 
			e . 
			gpuResult at: i
		} ].

	compare doWithIndex: [ :tuple :i |
		self assert: (tuple at: 1) <= 1.00000000001 ].
	x := compare select: [ :tuplex | (tuplex at: 1) ~= 1.0 ].
	
	
	
]

{ #category : #tests }
AGPUMatMulFP32Test >> test_reproducible [
	| lhs rhs gpuResult gpuResult2 matrixSize compare x gpuResult2Array notright |
	matrixSize := 9.
	lhs := AGPUMatrix rows: matrixSize columns: matrixSize tabulate: [ :r :c |  1 / (r * c) asFloat].	
	rhs := lhs deepCopy. 

	AGPUMatMulFP32 reset.
	gpuResult := lhs @ rhs.
	AGPUMatMulFP32 reset.
	gpuResult2 := lhs @ rhs. 

	compare := OrderedCollection new.
	gpuResult2Array := gpuResult2 asArray.
	gpuResult asArray withIndexDo: [ :e :i | compare add: { 
		e / (gpuResult2Array at: i). 
		e. 
		(gpuResult2Array at: i).
		i } ].
	notright := compare select: [ :xx | (xx at: 1) ~= 1.0 ].
	self assert: notright size equals: 0. "Upon failure, inspect 'notright' "

	
	
]
