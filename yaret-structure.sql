-- MySQL dump 10.16  Distrib 10.2.13-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: ret
-- ------------------------------------------------------
-- Server version	10.2.13-MariaDB-10.2.13+maria~xenial-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `eventnames`
--

DROP TABLE IF EXISTS `eventnames`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `eventnames` (
  `name` varchar(64) NOT NULL,
  `id` int(10) unsigned NOT NULL,
  `lang` varchar(8) NOT NULL DEFAULT '',
  `maxruntime` int(10) unsigned DEFAULT 7200,
  `planes` set('fire','water','air','life','death','earth') DEFAULT NULL,
  PRIMARY KEY (`id`,`lang`),
  KEY `id` (`id`),
  KEY `i_lang` (`lang`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `events`
--

DROP TABLE IF EXISTS `events`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `events` (
  `shardid` int(10) unsigned NOT NULL,
  `zoneid` int(10) unsigned NOT NULL,
  `eventid` int(10) unsigned NOT NULL,
  `starttime` int(10) unsigned NOT NULL,
  `endtime` int(10) unsigned DEFAULT 0,
  PRIMARY KEY (`shardid`,`zoneid`,`eventid`,`starttime`),
  KEY `zoneid` (`zoneid`),
  KEY `eventid` (`eventid`),
  KEY `end_index` (`endtime`),
  CONSTRAINT `events_ibfk_1` FOREIGN KEY (`shardid`) REFERENCES `shards` (`id`),
  CONSTRAINT `events_ibfk_2` FOREIGN KEY (`zoneid`) REFERENCES `zones` (`id`),
  CONSTRAINT `events_ibfk_3` FOREIGN KEY (`eventid`) REFERENCES `eventnames` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `maps`
--

DROP TABLE IF EXISTS `maps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `maps` (
  `map` varchar(32) DEFAULT NULL,
  `id` smallint(5) unsigned NOT NULL,
  `lang` varchar(8) NOT NULL,
  PRIMARY KEY (`id`,`lang`),
  KEY `i_lang` (`lang`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `shards`
--

DROP TABLE IF EXISTS `shards`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `shards` (
  `dc` varchar(8) NOT NULL,
  `id` int(10) unsigned NOT NULL,
  `name` varchar(16) NOT NULL,
  `pvp` tinyint(1) DEFAULT 0,
  `lang` varchar(8) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `dc` (`dc`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `zones`
--

DROP TABLE IF EXISTS `zones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `zones` (
  `name` varchar(32) NOT NULL,
  `id` int(10) unsigned NOT NULL,
  `lang` varchar(8) NOT NULL DEFAULT '',
  `mapid` smallint(5) unsigned NOT NULL,
  `maxlevel` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`,`lang`),
  KEY `id` (`id`),
  KEY `mapid` (`mapid`),
  KEY `lang` (`lang`),
  CONSTRAINT `zones_ibfk_1` FOREIGN KEY (`mapid`) REFERENCES `maps` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2018-03-20 13:40:27
