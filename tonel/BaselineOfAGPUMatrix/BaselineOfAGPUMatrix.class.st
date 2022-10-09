Class {
	#name : #BaselineOfAGPUMatrix,
	#superclass : #BaselineOf,
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
