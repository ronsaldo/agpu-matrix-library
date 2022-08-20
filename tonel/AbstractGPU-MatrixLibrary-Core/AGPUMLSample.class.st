Class {
	#name : #AGPUMLSample,
	#superclass : #Object,
	#pools : [
		'AGPUConstants'
	],
	#category : #'AbstractGPU-MatrixLibrary-Core'
}

{ #category : #'as yet unclassified' }
AGPUMLSample class >> exampleQuickSample [
	| device shader shaderCompiler |
	device := AGPU mainDevice.

	shader := ''.

	shaderCompiler := device createOfflineShaderCompiler.
]

{ #category : #'see class side' }
AGPUMLSample >> seeClassSide [
]
