Class {
	#name : #BaselineOfAGPUMatrix,
	#superclass : #Object,
	#category : #BaselineOfAGPUMatrix
}

{ #category : #baselines }
BaselineOfAGPUMatrix >> baseline: spec [
    <baseline>
	spec 
		for: #common
		do: [ 
			spec package: #'AbstractGPU-MatrixLibrary-Core'
			].

]
