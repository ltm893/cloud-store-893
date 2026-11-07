package com.cloudstore.lister.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProductBarcodeTest {

    @Test
    fun upcWinsOverTheCode128OnTheSameBottle() {
        val selection = ProductBarcode.preferred(
            listOf(
                ProductBarcode.Read(ProductBarcode.Symbology.CODE_128, "00000432500170"),
                ProductBarcode.Read(ProductBarcode.Symbology.EAN_13, "0080432500170")
            )
        )
        assertEquals(ProductBarcode.Symbology.UPC_A, selection?.symbology)
        assertEquals("080432500170", selection?.value)
        assertEquals(listOf("00000432500170"), selection?.ignored?.map { it.value })
    }

    @Test
    fun aRealEan13KeepsAll13Digits() {
        val selection = ProductBarcode.preferred(
            listOf(ProductBarcode.Read(ProductBarcode.Symbology.EAN_13, "8008385000068"))
        )
        assertEquals(ProductBarcode.Symbology.EAN_13, selection?.symbology)
        assertEquals("8008385000068", selection?.value)
    }

    @Test
    fun code128IsKeptWhenItIsTheOnlyCode() {
        val selection = ProductBarcode.preferred(
            listOf(ProductBarcode.Read(ProductBarcode.Symbology.CODE_128, "00000432500170"))
        )
        assertEquals(ProductBarcode.Symbology.CODE_128, selection?.symbology)
        assertEquals("00000432500170", selection?.value)
    }

    @Test
    fun aLeadingApostropheIsNotPartOfTheUpc() {
        assertEquals(
            "080432500170",
            ProductBarcode.catalogValue(ProductBarcode.Symbology.EAN_13, "'080432500170")
        )
    }

    @Test
    fun aUpcIsAcceptedOnTheFirstFrame() {
        assertEquals(
            ProductBarcode.Decision.Accept,
            ProductBarcode.decide(ProductBarcode.Symbology.UPC_A, null, 1_000L)
        )
    }

    @Test
    fun code128WaitsForAUpcThenIsAccepted() {
        assertEquals(
            ProductBarcode.Decision.Wait,
            ProductBarcode.decide(ProductBarcode.Symbology.CODE_128, null, 1_000L)
        )
        assertEquals(
            ProductBarcode.Decision.Wait,
            ProductBarcode.decide(ProductBarcode.Symbology.CODE_128, 1_000L, 1_200L)
        )
        assertEquals(
            ProductBarcode.Decision.Accept,
            ProductBarcode.decide(
                ProductBarcode.Symbology.CODE_128,
                1_000L,
                1_000L + ProductBarcode.NON_RETAIL_HOLD_MS
            )
        )
    }

    @Test
    fun blankReadsAreIgnored() {
        assertNull(
            ProductBarcode.preferred(
                listOf(ProductBarcode.Read(ProductBarcode.Symbology.EAN_13, "   "))
            )
        )
    }
}
